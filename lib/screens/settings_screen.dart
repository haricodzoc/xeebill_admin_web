import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../utils/app_colors.dart';

enum _NotifyStatus {
  idle,
  loadingUsers,
  updating,
  completed,
  failed,
}

class _SelectableUser {
  final String id;
  final String name;
  final String email;
  final String phone;
  bool selected;

  _SelectableUser({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    this.selected = false,
  });

  String get label {
    if (name.isNotEmpty) return name;
    if (email.isNotEmpty) return email;
    return id;
  }

  String get subtitle {
    final parts = <String>[
      if (email.isNotEmpty) email,
      if (phone.isNotEmpty) phone,
    ];
    return parts.isEmpty ? id : parts.join('  ·  ');
  }
}

class SettingsScreen extends StatefulWidget {
  final String? userId;
  final String? userDocId;
  final String? userName;

  const SettingsScreen({
    super.key,
    this.userId,
    this.userDocId,
    this.userName,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = true;
  String? _loadError;
  DateTime _taxRateUpdatedOn = DateTime.now();

  final TextEditingController _searchController = TextEditingController();
  List<_SelectableUser> _users = [];
  String _searchQuery = '';

  _NotifyStatus _status = _NotifyStatus.idle;
  int _progressDone = 0;
  int _progressTotal = 0;
  int _successCount = 0;
  int _failedCount = 0;
  String _currentUserLabel = '';
  String _statusMessage = 'Select users, then send notification';

  bool get _isSending =>
      _status == _NotifyStatus.loadingUsers ||
      _status == _NotifyStatus.updating;

  List<_SelectableUser> get _filteredUsers {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _users;
    return _users.where((u) {
      return u.name.toLowerCase().contains(q) ||
          u.email.toLowerCase().contains(q) ||
          u.phone.toLowerCase().contains(q) ||
          u.id.toLowerCase().contains(q);
    }).toList();
  }

  List<_SelectableUser> get _selectedUsers =>
      _users.where((u) => u.selected).toList();

  int get _selectedCount => _selectedUsers.length;

  bool get _allFilteredSelected {
    final filtered = _filteredUsers;
    return filtered.isNotEmpty && filtered.every((u) => u.selected);
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text);
    });
    _loadSettings();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final preferredDocId = widget.userDocId?.trim() ?? '';
      final usersSnap =
          await FirebaseFirestore.instance.collection('users').get();

      final users = usersSnap.docs.map((doc) {
        final data = doc.data();
        return _SelectableUser(
          id: doc.id,
          name: (data['name'] ?? '').toString().trim(),
          email: (data['email'] ?? '').toString().trim(),
          phone: (data['phone'] ?? '').toString().trim(),
          selected: preferredDocId.isNotEmpty && doc.id == preferredDocId,
        );
      }).toList()
        ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

      _users = users;

      // Prefill date from preferred user, else first selected/existing flag.
      DocumentSnapshot<Map<String, dynamic>>? settingsDoc;
      final seedId = preferredDocId.isNotEmpty
          ? preferredDocId
          : (users.isNotEmpty ? users.first.id : null);
      if (seedId != null) {
        settingsDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(seedId)
            .collection('settings')
            .doc('app')
            .get();
      }

      if (settingsDoc != null &&
          settingsDoc.exists &&
          settingsDoc.data() != null) {
        final existing = _parseDate(
          settingsDoc.data()!['tax_rate_updated_date'] ??
              settingsDoc.data()!['taxRateUpdatedDate'],
        );
        if (existing != null) {
          _taxRateUpdatedOn = DateTime(
            existing.year,
            existing.month,
            existing.day,
          );
        }
      }

      _statusMessage = users.isEmpty
          ? 'No users found'
          : preferredDocId.isNotEmpty && _selectedCount == 1
              ? '1 user preselected — add more or send'
              : 'Select users, then send notification';
    } catch (e) {
      _loadError = 'Error loading users: $e';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_loadError!)),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _selectAllFiltered() {
    setState(() {
      for (final u in _filteredUsers) {
        u.selected = true;
      }
      _statusMessage = '$_selectedCount user${_selectedCount == 1 ? '' : 's'} selected';
    });
  }

  void _clearSelection() {
    setState(() {
      for (final u in _users) {
        u.selected = false;
      }
      _statusMessage = 'Select users, then send notification';
    });
  }

  void _toggleSelectAllFiltered() {
    if (_allFilteredSelected) {
      setState(() {
        for (final u in _filteredUsers) {
          u.selected = false;
        }
        _statusMessage = '$_selectedCount user${_selectedCount == 1 ? '' : 's'} selected';
      });
    } else {
      _selectAllFiltered();
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _taxRateUpdatedOn,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Tax rate updated on',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _taxRateUpdatedOn = DateTime(picked.year, picked.month, picked.day);
    });
  }

  Future<void> _sendNotificationNow() async {
    final targets = _selectedUsers;
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select at least one user'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final dateLabel = DateFormat('dd MMM yyyy').format(_taxRateUpdatedOn);
    final isAll = targets.length == _users.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAll ? 'Notify all users?' : 'Notify selected users?'),
        content: Text(
          isAll
              ? 'Set tax_rate_updated and tax_rate_updated_date ($dateLabel) '
                  'for all ${_users.length} users.'
              : 'Set tax_rate_updated and tax_rate_updated_date ($dateLabel) '
                  'for ${targets.length} selected user'
                  '${targets.length == 1 ? '' : 's'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
            ),
            child: Text(isAll ? 'Send to all' : 'Send to selected'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() {
      _status = _NotifyStatus.updating;
      _progressDone = 0;
      _progressTotal = targets.length;
      _successCount = 0;
      _failedCount = 0;
      _currentUserLabel = '';
      _statusMessage = 'Updating 0 of ${targets.length}…';
    });

    try {
      final dateOnly = DateTime(
        _taxRateUpdatedOn.year,
        _taxRateUpdatedOn.month,
        _taxRateUpdatedOn.day,
      );
      final payload = <String, dynamic>{
        'tax_rate_updated': true,
        'tax_rate_updated_date': Timestamp.fromDate(dateOnly),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      const chunkSize = 25;
      for (var start = 0; start < targets.length; start += chunkSize) {
        final end = (start + chunkSize).clamp(0, targets.length);
        final chunk = targets.sublist(start, end);
        final batch = FirebaseFirestore.instance.batch();

        for (final user in chunk) {
          batch.set(
            FirebaseFirestore.instance
                .collection('users')
                .doc(user.id)
                .collection('settings')
                .doc('app'),
            payload,
            SetOptions(merge: true),
          );
        }

        if (!mounted) return;
        setState(() {
          _currentUserLabel = chunk.last.label;
          _statusMessage =
              'Updating ${start + 1}–$end of ${targets.length}…';
        });

        try {
          await batch.commit();
          if (!mounted) return;
          setState(() {
            _successCount += chunk.length;
            _progressDone = end;
            _statusMessage =
                'Updated $_progressDone of $_progressTotal users…';
          });
        } catch (_) {
          for (final user in chunk) {
            if (!mounted) return;
            setState(() {
              _currentUserLabel = user.label;
              _statusMessage =
                  'Retrying ${_progressDone + 1} of $_progressTotal…';
            });
            try {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.id)
                  .collection('settings')
                  .doc('app')
                  .set(payload, SetOptions(merge: true));
              if (!mounted) return;
              setState(() {
                _successCount++;
                _progressDone++;
              });
            } catch (_) {
              if (!mounted) return;
              setState(() {
                _failedCount++;
                _progressDone++;
              });
            }
          }
          if (!mounted) return;
          setState(() {
            _statusMessage =
                'Updated $_progressDone of $_progressTotal users…';
          });
        }

        await Future<void>.delayed(const Duration(milliseconds: 16));
      }

      if (!mounted) return;
      final ok = _failedCount == 0;
      setState(() {
        _status = ok ? _NotifyStatus.completed : _NotifyStatus.failed;
        _currentUserLabel = '';
        _statusMessage = ok
            ? 'Completed: updated $_successCount users'
            : 'Finished with errors: $_successCount updated, $_failedCount failed';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_statusMessage),
          backgroundColor: ok ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _NotifyStatus.failed;
        _statusMessage = 'Failed: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send notification: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Color _statusColor() {
    switch (_status) {
      case _NotifyStatus.idle:
        return AppColors.primaryGrey;
      case _NotifyStatus.loadingUsers:
      case _NotifyStatus.updating:
        return AppColors.primaryGreen;
      case _NotifyStatus.completed:
        return AppColors.successGreen;
      case _NotifyStatus.failed:
        return AppColors.primaryRed;
    }
  }

  String _statusTitle() {
    switch (_status) {
      case _NotifyStatus.idle:
        return 'Idle';
      case _NotifyStatus.loadingUsers:
        return 'Loading users';
      case _NotifyStatus.updating:
        return 'In progress';
      case _NotifyStatus.completed:
        return 'Completed';
      case _NotifyStatus.failed:
        return 'Failed / Partial';
    }
  }

  Widget _buildStatusPanel() {
    final progress = _progressTotal <= 0
        ? null
        : (_progressDone / _progressTotal).clamp(0.0, 1.0);
    final color = _statusColor();
    final percent = progress == null ? null : (progress * 100).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                'STATUS: ${_statusTitle().toUpperCase()}',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const Spacer(),
              if (percent != null)
                Text(
                  '$percent%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: _isSending ? progress : (progress ?? 0),
              minHeight: 10,
              backgroundColor: Colors.white,
              color: color,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _statusMessage,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryText,
            ),
          ),
          if (_currentUserLabel.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Current: $_currentUserLabel',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ],
          if (_progressTotal > 0) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _statChip('Total', '$_progressTotal', AppColors.primaryGrey),
                _statChip('Done', '$_progressDone', AppColors.primaryGreen),
                _statChip('Success', '$_successCount', AppColors.successGreen),
                if (_failedCount > 0)
                  _statChip('Failed', '$_failedCount', AppColors.primaryRed),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildUserPicker() {
    final filtered = _filteredUsers;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8ECF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'USERS',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey[600],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$_selectedCount selected / ${_users.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _searchController,
                  enabled: !_isSending,
                  decoration: InputDecoration(
                    hintText: 'Search name, email, phone, id…',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE8ECF0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE8ECF0)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _isSending ? null : _toggleSelectAllFiltered,
                      icon: Icon(
                        _allFilteredSelected
                            ? Icons.deselect
                            : Icons.select_all,
                        size: 16,
                      ),
                      label: Text(
                        _allFilteredSelected
                            ? 'Clear filtered'
                            : 'Select filtered',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _isSending || _users.isEmpty
                          ? null
                          : () {
                              setState(() {
                                for (final u in _users) {
                                  u.selected = true;
                                }
                                _statusMessage =
                                    '$_selectedCount users selected';
                              });
                            },
                      icon: const Icon(Icons.done_all, size: 16),
                      label: const Text('Select all'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _isSending || _selectedCount == 0
                          ? null
                          : _clearSelection,
                      icon: const Icon(Icons.clear_all, size: 16),
                      label: const Text('Clear'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            height: 280,
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'No users match your search',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: Color(0xFFE8ECF0)),
                    itemBuilder: (context, index) {
                      final user = filtered[index];
                      return CheckboxListTile(
                        value: user.selected,
                        dense: true,
                        enabled: !_isSending,
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: AppColors.primaryGreen,
                        title: Text(
                          user.label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                        subtitle: Text(
                          user.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        onChanged: _isSending
                            ? null
                            : (val) {
                                setState(() {
                                  user.selected = val ?? false;
                                  _statusMessage = _selectedCount == 0
                                      ? 'Select users, then send notification'
                                      : '$_selectedCount user${_selectedCount == 1 ? '' : 's'} selected';
                                });
                              },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleName = (widget.userName ?? '').trim();

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.primaryText,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Settings',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            if (titleName.isNotEmpty)
              Text(
                titleName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[600],
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading || _isSending ? null : _loadSettings,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _loadError!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadSettings,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryGreen,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: const BorderSide(color: Color(0xFFE6E9ED)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'TAX RATE UPDATE',
                                  style: TextStyle(
                                    fontSize: 11,
                                    letterSpacing: 0.7,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Tax rate updated on',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primaryText,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                InkWell(
                                  onTap: _isSending ? null : _pickDate,
                                  borderRadius: BorderRadius.circular(10),
                                  child: InputDecorator(
                                    decoration: InputDecoration(
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: const BorderSide(
                                          color: Color(0xFFE8ECF0),
                                        ),
                                      ),
                                      suffixIcon: const Icon(
                                        Icons.calendar_today_outlined,
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 14,
                                      ),
                                    ),
                                    child: Text(
                                      DateFormat('dd MMM yyyy')
                                          .format(_taxRateUpdatedOn),
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primaryText,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _buildUserPicker(),
                                const SizedBox(height: 16),
                                _buildStatusPanel(),
                                const SizedBox(height: 20),
                                SizedBox(
                                  height: 46,
                                  child: ElevatedButton.icon(
                                    onPressed: _isSending ||
                                            _selectedCount == 0
                                        ? null
                                        : _sendNotificationNow,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primaryGreen,
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor:
                                          Colors.grey.shade300,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    icon: _isSending
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.notifications_active_outlined,
                                          ),
                                    label: Text(
                                      _isSending
                                          ? 'Sending…'
                                          : _selectedCount == 0
                                              ? 'Select users to send'
                                              : _selectedCount == _users.length
                                                  ? 'Send notification to all ($_selectedCount)'
                                                  : 'Send notification ($_selectedCount selected)',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Writes tax_rate_updated and tax_rate_updated_date '
                                  'to users/{id}/settings/app for the selected users.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
