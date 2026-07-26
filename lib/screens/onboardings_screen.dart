import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/onboarding_model.dart';
import '../utils/app_colors.dart';

class OnboardingsScreen extends StatefulWidget {
  const OnboardingsScreen({super.key});

  @override
  State<OnboardingsScreen> createState() => _OnboardingsScreenState();
}

class _OnboardingsScreenState extends State<OnboardingsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;
  List<OnboardingModel> _items = [];
  List<OnboardingModel> _filteredItems = [];
  OnboardingStatus? _statusFilter;
  String? _updatingId;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applyFilters);
    _fetchOnboardings();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchOnboardings() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final snap = await _firestore
          .collection('onboardings')
          .orderBy('createdAt', descending: true)
          .get();

      final items = <OnboardingModel>[];
      for (final doc in snap.docs) {
        try {
          items.add(OnboardingModel.fromFirestore(doc));
        } catch (e) {
          debugPrint('Error parsing onboarding ${doc.id}: $e');
        }
      }

      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
      _applyFilters();
    } catch (e) {
      // Fallback if createdAt index / field is missing.
      try {
        final snap = await _firestore.collection('onboardings').get();
        final items = snap.docs
            .map(OnboardingModel.fromFirestore)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        if (!mounted) return;
        setState(() {
          _items = items;
          _isLoading = false;
        });
        _applyFilters();
      } catch (inner) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Error loading onboardings: $inner';
          _isLoading = false;
        });
      }
    }
  }

  void _applyFilters() {
    final q = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredItems = _items.where((item) {
        if (_statusFilter != null && item.status != _statusFilter) {
          return false;
        }
        if (q.isEmpty) return true;
        return item.name.toLowerCase().contains(q) ||
            item.phone.toLowerCase().contains(q) ||
            item.location.toLowerCase().contains(q) ||
            item.address.toLowerCase().contains(q) ||
            item.shopType.toLowerCase().contains(q) ||
            item.remarks.toLowerCase().contains(q);
      }).toList();
    });
  }

  Color _statusColor(OnboardingStatus status) {
    switch (status) {
      case OnboardingStatus.pending:
        return const Color(0xFFC27803);
      case OnboardingStatus.inProgress:
        return AppColors.primaryGreen;
      case OnboardingStatus.completed:
        return AppColors.successGreen;
    }
  }

  IconData _statusIcon(OnboardingStatus status) {
    switch (status) {
      case OnboardingStatus.pending:
        return Icons.schedule_rounded;
      case OnboardingStatus.inProgress:
        return Icons.sync_rounded;
      case OnboardingStatus.completed:
        return Icons.check_circle_outline_rounded;
    }
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final s = parts.first;
      return s.substring(0, s.length >= 2 ? 2 : 1).toUpperCase();
    }
    return ('${parts.first[0]}${parts.last[0]}').toUpperCase();
  }

  Future<void> _updateStatus(
    OnboardingModel item,
    OnboardingStatus status,
  ) async {
    if (item.status == status) return;
    setState(() => _updatingId = item.id);
    try {
      final now = DateTime.now();
      await _firestore.collection('onboardings').doc(item.id).set({
        'status': status.firestoreValue,
        'updatedAt': Timestamp.fromDate(now),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        final index = _items.indexWhere((e) => e.id == item.id);
        if (index != -1) {
          _items[index] = item.copyWith(status: status, updatedAt: now);
        }
      });
      _applyFilters();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Status updated to ${status.label}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _updatingId = null);
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Not set';
    return DateFormat('dd MMM yyyy').format(date);
  }

  Future<void> _pickAndSaveDate({
    required OnboardingModel item,
    required String field,
    required DateTime? current,
    required String label,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: label,
    );
    if (picked == null || !mounted) return;

    // Keep time-less date (local midnight) for consistent display.
    final dateOnly = DateTime(picked.year, picked.month, picked.day);
    if (current != null &&
        current.year == dateOnly.year &&
        current.month == dateOnly.month &&
        current.day == dateOnly.day) {
      return;
    }

    setState(() => _updatingId = item.id);
    try {
      final now = DateTime.now();
      await _firestore.collection('onboardings').doc(item.id).set({
        field: Timestamp.fromDate(dateOnly),
        'updatedAt': Timestamp.fromDate(now),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        final index = _items.indexWhere((e) => e.id == item.id);
        if (index == -1) return;
        if (field == 'recentEnquiryDate') {
          _items[index] = item.copyWith(
            recentEnquiryDate: dateOnly,
            updatedAt: now,
          );
        } else if (field == 'acceptedImplementationDate') {
          _items[index] = item.copyWith(
            acceptedImplementationDate: dateOnly,
            updatedAt: now,
          );
        }
      });
      _applyFilters();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label updated'),
          backgroundColor: AppColors.successGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update $label: $e'),
          backgroundColor: AppColors.primaryRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _updatingId = null);
    }
  }

  Widget _dateActionTile({
    required String label,
    required DateTime? value,
    required VoidCallback? onTap,
    required IconData icon,
  }) {
    final hasValue = value != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: hasValue
                      ? AppColors.primaryGreen.withValues(alpha: 0.1)
                      : const Color(0xFFF1F3F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: hasValue
                      ? AppColors.primaryGreen
                      : AppColors.primaryGrey,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 0.6,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatDate(value),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: hasValue
                            ? AppColors.primaryText
                            : AppColors.primaryGrey,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openInGoogleMaps(String location) async {
    final query = location.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No location available')),
      );
      return;
    }

    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}',
    );
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Google Maps')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open Google Maps: $e')),
      );
    }
  }

  Future<String?> _fetchCurrentLatLng({
    required void Function(String message) onError,
  }) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        onError('Location services are disabled. Please enable GPS/location.');
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        onError('Location permission denied.');
        return null;
      }
      if (permission == LocationPermission.deniedForever) {
        onError(
          'Location permission permanently denied. Allow location access in browser settings.',
        );
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      return '${position.latitude.toStringAsFixed(6)},${position.longitude.toStringAsFixed(6)}';
    } catch (e) {
      onError('Failed to fetch current location: $e');
      return null;
    }
  }

  Future<void> _showAddCustomerDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();
    final locationController = TextEditingController();
    final remarksController = TextEditingController();
    String? shopType;
    var status = OnboardingStatus.pending;
    DateTime? recentEnquiryDate = DateTime.now();
    DateTime? acceptedImplementationDate;
    var isSaving = false;
    var isFetchingLocation = false;

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Add Onboarding Customer'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: nameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Customer name *',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty)
                                  ? 'Name is required'
                                  : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          maxLength: 10,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Phone *',
                            hintText: '10 digit mobile number',
                            border: OutlineInputBorder(),
                            counterText: '',
                          ),
                          validator: (v) {
                            final value = v?.trim() ?? '';
                            if (value.isEmpty) return 'Phone is required';
                            if (value.length != 10) {
                              return 'Mobile number must be 10 digits';
                            }
                            if (!RegExp(r'^[6-9]\d{9}$').hasMatch(value)) {
                              return 'Enter a valid mobile number';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: shopType,
                          decoration: const InputDecoration(
                            labelText: 'Shop type *',
                            border: OutlineInputBorder(),
                          ),
                          items: kOnboardingShopTypes
                              .map(
                                (type) => DropdownMenuItem(
                                  value: type,
                                  child: Text(type),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            setDialogState(() => shopType = val);
                          },
                          validator: (v) =>
                              (v == null || v.trim().isEmpty)
                                  ? 'Shop type is required'
                                  : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: addressController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Address',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: locationController,
                          decoration: InputDecoration(
                            labelText: 'Location',
                            hintText: 'Place name or lat,lng',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.place_outlined),
                            suffixIcon: isFetchingLocation
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : IconButton(
                                    tooltip: 'Use current location',
                                    icon: Icon(
                                      Icons.my_location,
                                      color: AppColors.primaryGreen,
                                    ),
                                    onPressed: isSaving
                                        ? null
                                        : () async {
                                            setDialogState(
                                              () => isFetchingLocation = true,
                                            );
                                            final coords =
                                                await _fetchCurrentLatLng(
                                              onError: (message) {
                                                if (dialogContext.mounted) {
                                                  ScaffoldMessenger.of(
                                                    dialogContext,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(message),
                                                      backgroundColor:
                                                          Colors.orange,
                                                    ),
                                                  );
                                                }
                                              },
                                            );
                                            if (coords != null) {
                                              locationController.text = coords;
                                            }
                                            setDialogState(
                                              () => isFetchingLocation = false,
                                            );
                                          },
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: isSaving || isFetchingLocation
                                ? null
                                : () async {
                                    setDialogState(
                                      () => isFetchingLocation = true,
                                    );
                                    final coords = await _fetchCurrentLatLng(
                                      onError: (message) {
                                        if (dialogContext.mounted) {
                                          ScaffoldMessenger.of(
                                            dialogContext,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(message),
                                              backgroundColor: Colors.orange,
                                            ),
                                          );
                                        }
                                      },
                                    );
                                    if (coords != null) {
                                      locationController.text = coords;
                                    }
                                    setDialogState(
                                      () => isFetchingLocation = false,
                                    );
                                  },
                            icon: const Icon(Icons.my_location, size: 18),
                            label: Text(
                              isFetchingLocation
                                  ? 'Fetching location…'
                                  : 'Use current location (lat, lng)',
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: remarksController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Remarks',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<OnboardingStatus>(
                          initialValue: status,
                          decoration: const InputDecoration(
                            labelText: 'Status',
                            border: OutlineInputBorder(),
                          ),
                          items: OnboardingStatus.values
                              .map(
                                (s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(s.label),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            if (val == null) return;
                            setDialogState(() => status = val);
                          },
                        ),
                        const SizedBox(height: 12),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.event_outlined,
                            color: AppColors.primaryGreen,
                          ),
                          title: const Text('Recent enquiry date'),
                          subtitle: Text(
                            recentEnquiryDate == null
                                ? 'Tap to set'
                                : DateFormat('dd MMM yyyy')
                                    .format(recentEnquiryDate!),
                          ),
                          trailing: const Icon(Icons.calendar_today_outlined),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: dialogContext,
                              initialDate:
                                  recentEnquiryDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                              helpText: 'Recent enquiry date',
                            );
                            if (picked != null) {
                              setDialogState(
                                () => recentEnquiryDate = DateTime(
                                  picked.year,
                                  picked.month,
                                  picked.day,
                                ),
                              );
                            }
                          },
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.event_available_outlined,
                            color: AppColors.primaryGreen,
                          ),
                          title: const Text('Accepted implementation date'),
                          subtitle: Text(
                            acceptedImplementationDate == null
                                ? 'Tap to set'
                                : DateFormat('dd MMM yyyy')
                                    .format(acceptedImplementationDate!),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (acceptedImplementationDate != null)
                                IconButton(
                                  tooltip: 'Clear',
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    setDialogState(
                                      () => acceptedImplementationDate = null,
                                    );
                                  },
                                ),
                              const Icon(Icons.calendar_today_outlined),
                            ],
                          ),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: dialogContext,
                              initialDate: acceptedImplementationDate ??
                                  DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                              helpText: 'Accepted implementation date',
                            );
                            if (picked != null) {
                              setDialogState(
                                () => acceptedImplementationDate = DateTime(
                                  picked.year,
                                  picked.month,
                                  picked.day,
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() => isSaving = true);
                          try {
                            final now = DateTime.now();
                            await _firestore.collection('onboardings').add({
                              'name': nameController.text.trim(),
                              'phone': phoneController.text.trim(),
                              'shopType': shopType?.trim() ?? '',
                              'address': addressController.text.trim(),
                              'location': locationController.text.trim(),
                              'remarks': remarksController.text.trim(),
                              'status': status.firestoreValue,
                              'recentEnquiryDate': recentEnquiryDate == null
                                  ? null
                                  : Timestamp.fromDate(recentEnquiryDate!),
                              'acceptedImplementationDate':
                                  acceptedImplementationDate == null
                                      ? null
                                      : Timestamp.fromDate(
                                          acceptedImplementationDate!,
                                        ),
                              'createdAt': Timestamp.fromDate(now),
                              'updatedAt': Timestamp.fromDate(now),
                            });
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext, true);
                            }
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to add customer: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                  ),
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    phoneController.dispose();
    addressController.dispose();
    locationController.dispose();
    remarksController.dispose();

    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Customer added successfully'),
          backgroundColor: Colors.green,
        ),
      );
      await _fetchOnboardings();
    }
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
          color: Colors.grey[600],
        ),
      ),
    );
  }

  void _showDetails(OnboardingModel item) {
    final statusColor = _statusColor(item.status);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.78,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (ctx, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E5E9),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: statusColor.withValues(alpha: 0.12),
                        child: Text(
                          _initials(item.name),
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name.isEmpty
                                  ? 'Unnamed customer'
                                  : item.name,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1F2933),
                                height: 1.2,
                              ),
                            ),
                            if (item.shopType.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                item.shopType,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.primaryGreen,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            _StatusChip(
                              label: item.status.label,
                              color: statusColor,
                              icon: _statusIcon(item.status),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _sectionLabel('Contact & shop'),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE8ECF0)),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    child: Column(
                      children: [
                        _DetailRow(
                          icon: Icons.phone_outlined,
                          label: 'Phone',
                          value: item.phone.isEmpty ? '—' : item.phone,
                        ),
                        const Divider(height: 1, color: Color(0xFFE8ECF0)),
                        _DetailRow(
                          icon: Icons.storefront_outlined,
                          label: 'Shop type',
                          value: item.shopType.isEmpty ? '—' : item.shopType,
                        ),
                        const Divider(height: 1, color: Color(0xFFE8ECF0)),
                        _DetailRow(
                          icon: Icons.home_outlined,
                          label: 'Address',
                          value: item.address.isEmpty ? '—' : item.address,
                        ),
                        const Divider(height: 1, color: Color(0xFFE8ECF0)),
                        _DetailRow(
                          icon: Icons.place_outlined,
                          label: 'Location',
                          value: item.location.isEmpty ? '—' : item.location,
                          trailing: item.location.isEmpty
                              ? null
                              : TextButton(
                                  onPressed: () =>
                                      _openInGoogleMaps(item.location),
                                  child: const Text('Maps'),
                                ),
                          onTap: item.location.isEmpty
                              ? null
                              : () => _openInGoogleMaps(item.location),
                        ),
                        if (item.remarks.isNotEmpty) ...[
                          const Divider(height: 1, color: Color(0xFFE8ECF0)),
                          _DetailRow(
                            icon: Icons.notes_outlined,
                            label: 'Remarks',
                            value: item.remarks,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel('Schedule'),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE8ECF0)),
                    ),
                    child: Column(
                      children: [
                        _dateActionTile(
                          label: 'Recent enquiry',
                          value: item.recentEnquiryDate,
                          icon: Icons.event_outlined,
                          onTap: () async {
                            Navigator.pop(ctx);
                            await _pickAndSaveDate(
                              item: item,
                              field: 'recentEnquiryDate',
                              current: item.recentEnquiryDate,
                              label: 'Recent enquiry date',
                            );
                          },
                        ),
                        const Divider(height: 1, color: Color(0xFFE8ECF0)),
                        _dateActionTile(
                          label: 'Accepted implementation',
                          value: item.acceptedImplementationDate,
                          icon: Icons.event_available_outlined,
                          onTap: () async {
                            Navigator.pop(ctx);
                            await _pickAndSaveDate(
                              item: item,
                              field: 'acceptedImplementationDate',
                              current: item.acceptedImplementationDate,
                              label: 'Accepted implementation date',
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel('Status'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: OnboardingStatus.values.map((status) {
                      final selected = item.status == status;
                      final color = _statusColor(status);
                      return ChoiceChip(
                        label: Text(status.label),
                        selected: selected,
                        avatar: Icon(
                          _statusIcon(status),
                          size: 16,
                          color: selected ? color : AppColors.primaryGrey,
                        ),
                        selectedColor: color.withValues(alpha: 0.14),
                        side: BorderSide(
                          color: selected
                              ? color.withValues(alpha: 0.45)
                              : const Color(0xFFE2E5E9),
                        ),
                        labelStyle: TextStyle(
                          color: selected ? color : AppColors.primaryGrey,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                        onSelected: (_) async {
                          Navigator.pop(ctx);
                          await _updateStatus(item, status);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Created ${DateFormat('dd MMM yyyy, HH:mm').format(item.createdAt)}'
                    '  ·  Updated ${DateFormat('dd MMM yyyy, HH:mm').format(item.updatedAt)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFilterChip(String label, OnboardingStatus? value) {
    final selected = _statusFilter == value;
    return FilterChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) {
        setState(() => _statusFilter = value);
        _applyFilters();
      },
      padding: const EdgeInsets.symmetric(horizontal: 4),
      selectedColor: AppColors.primaryGreen.withValues(alpha: 0.12),
      backgroundColor: Colors.white,
      side: BorderSide(
        color: selected
            ? AppColors.primaryGreen.withValues(alpha: 0.45)
            : const Color(0xFFE2E5E9),
      ),
      labelStyle: TextStyle(
        color: selected ? AppColors.primaryGreen : AppColors.primaryGrey,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        fontSize: 13,
      ),
    );
  }

  Future<void> _confirmAndDelete(OnboardingModel item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete customer'),
        content: Text(
          'Delete "${item.name.isEmpty ? 'this customer' : item.name}"?\n\n'
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryRed,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await _firestore.collection('onboardings').doc(item.id).delete();
      if (!mounted) return;
      setState(() {
        _items.removeWhere((e) => e.id == item.id);
      });
      _applyFilters();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Customer deleted'),
          backgroundColor: Color(0xFF396F55),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete: $e'),
          backgroundColor: AppColors.primaryRed,
        ),
      );
    }
  }

  Widget _buildCard(OnboardingModel item) {
    final isUpdating = _updatingId == item.id;
    final statusColor = _statusColor(item.status);
    final displayName = item.name.isEmpty ? 'Unnamed customer' : item.name;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6E9ED)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: statusColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _showDetails(item),
                      onLongPress: () => _confirmAndDelete(item),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor:
                                statusColor.withValues(alpha: 0.12),
                            child: Text(
                              _initials(displayName),
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1F2933),
                                    height: 1.25,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  [
                                    if (item.shopType.isNotEmpty) item.shopType,
                                    if (item.phone.isNotEmpty) item.phone,
                                  ].join('  ·  '),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[700],
                                    height: 1.3,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (item.location.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.place_outlined,
                                        size: 13,
                                        color: Colors.grey[500],
                                      ),
                                      const SizedBox(width: 3),
                                      Expanded(
                                        child: Text(
                                          item.location,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StatusChip(
                            label: item.status.label,
                            color: statusColor,
                            icon: _statusIcon(item.status),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFEEF1F4)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _dateActionTile(
                              label: 'Enquiry',
                              value: item.recentEnquiryDate,
                              icon: Icons.event_outlined,
                              onTap: isUpdating
                                  ? null
                                  : () => _pickAndSaveDate(
                                        item: item,
                                        field: 'recentEnquiryDate',
                                        current: item.recentEnquiryDate,
                                        label: 'Recent enquiry date',
                                      ),
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 44,
                            color: const Color(0xFFE8ECF0),
                          ),
                          Expanded(
                            child: _dateActionTile(
                              label: 'Implementation',
                              value: item.acceptedImplementationDate,
                              icon: Icons.event_available_outlined,
                              onTap: isUpdating
                                  ? null
                                  : () => _pickAndSaveDate(
                                        item: item,
                                        field: 'acceptedImplementationDate',
                                        current:
                                            item.acceptedImplementationDate,
                                        label: 'Accepted implementation date',
                                      ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          'STATUS',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 0.6,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: isUpdating
                              ? const Align(
                                  alignment: Alignment.centerLeft,
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : DropdownButtonHideUnderline(
                                  child: DropdownButton<OnboardingStatus>(
                                    value: item.status,
                                    isDense: true,
                                    icon: Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      color: Colors.grey[500],
                                    ),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: statusColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    items: OnboardingStatus.values
                                        .map(
                                          (s) => DropdownMenuItem(
                                            value: s,
                                            child: Text(s.label),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (val) {
                                      if (val == null) return;
                                      _updateStatus(item, val);
                                    },
                                  ),
                                ),
                        ),
                        TextButton(
                          onPressed: () => _showDetails(item),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primaryGreen,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Details'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              'Onboardings',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            if (!_isLoading)
              Text(
                '${_filteredItems.length} customer${_filteredItems.length == 1 ? '' : 's'}',
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
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _fetchOnboardings,
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddCustomerDialog,
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
        elevation: 2,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add Customer'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 48,
                          color: AppColors.primaryRed.withValues(alpha: 0.8),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _fetchOnboardings,
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
              : Column(
                  children: [
                    Container(
                      width: double.infinity,
                      color: Colors.white,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Search by name, phone, shop, location…',
                              hintStyle: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 14,
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: Colors.grey[500],
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF5F7F9),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE8ECF0),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: AppColors.primaryGreen,
                                  width: 1.2,
                                ),
                              ),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildFilterChip('All', null),
                              _buildFilterChip(
                                'Pending',
                                OnboardingStatus.pending,
                              ),
                              _buildFilterChip(
                                'In Progress',
                                OnboardingStatus.inProgress,
                              ),
                              _buildFilterChip(
                                'Completed',
                                OnboardingStatus.completed,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(height: 1, color: const Color(0xFFE8ECF0)),
                    Expanded(
                      child: _filteredItems.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 72,
                                    height: 72,
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryGreen
                                          .withValues(alpha: 0.08),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.groups_outlined,
                                      size: 36,
                                      color: AppColors.primaryGreen,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No customers found',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primaryText,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Try another filter or add a new customer',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    onPressed: _showAddCustomerDialog,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primaryGreen,
                                      foregroundColor: Colors.white,
                                    ),
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add Customer'),
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              color: AppColors.primaryGreen,
                              onRefresh: _fetchOnboardings,
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  14,
                                  16,
                                  96,
                                ),
                                itemCount: _filteredItems.length,
                                itemBuilder: (context, index) {
                                  return _buildCard(_filteredItems[index]);
                                },
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _StatusChip({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primaryGrey),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    color: onTap != null
                        ? AppColors.primaryGreen
                        : AppColors.primaryText,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: content,
    );
  }
}
