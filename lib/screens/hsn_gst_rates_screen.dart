import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/category_model.dart';
import '../utils/app_colors.dart';

class HsnGstRatesScreen extends StatefulWidget {
  final String userId;

  const HsnGstRatesScreen({super.key, required this.userId});

  @override
  State<HsnGstRatesScreen> createState() => _HsnGstRatesScreenState();
}

class _HsnGstRow {
  final String hsnCode;
  final List<CategoryModel> categories;

  const _HsnGstRow({
    required this.hsnCode,
    required this.categories,
  });

  double get displayRate {
    if (categories.isEmpty) return 0;
    return categories.first.taxPercentage;
  }

  bool get hasMixedRates {
    if (categories.length <= 1) return false;
    final first = categories.first.taxPercentage;
    return categories.any((c) => c.taxPercentage != first);
  }

  String get categorySummary {
    if (categories.length == 1) {
      return '${categories.first.name} (${categories.first.code})';
    }
    return '${categories.length} categories';
  }
}

class _HsnGstRatesScreenState extends State<HsnGstRatesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;
  List<_HsnGstRow> _rows = [];
  List<_HsnGstRow> _filteredRows = [];
  final Map<String, TextEditingController> _rateControllers = {};
  String? _updatingHsn;

  int _progressDone = 0;
  int _progressTotal = 0;
  String _progressStatus = '';
  String _progressDetail = '';
  int _liveCategoriesUpdated = 0;
  int _liveItemsUpdated = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applySearch);
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (final c in _rateControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _normalizeSixDigitHsn(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 6) return null;
    return digits;
  }

  String _normCode(dynamic raw) => (raw ?? '').toString().trim();

  Future<String?> _resolveUserDocumentId() async {
    final uid = widget.userId.trim();
    if (uid.isEmpty) return null;

    final byField = await _firestore
        .collection('users')
        .where('userId', isEqualTo: uid)
        .limit(1)
        .get();
    if (byField.docs.isNotEmpty) return byField.docs.first.id;

    final byId = await _firestore.collection('users').doc(uid).get();
    if (byId.exists) return uid;

    return null;
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userDocumentId = await _resolveUserDocumentId();
      if (userDocumentId == null) {
        setState(() {
          _errorMessage = 'User document not found';
          _isLoading = false;
        });
        return;
      }

      final snap = await _firestore
          .collection('users')
          .doc(userDocumentId)
          .collection('categories')
          .get();

      final grouped = <String, List<CategoryModel>>{};
      for (final doc in snap.docs) {
        final category = CategoryModel.fromFirestore(doc);
        final hsn = _normalizeSixDigitHsn(category.hsnCode);
        if (hsn == null) continue;
        grouped.putIfAbsent(hsn, () => []).add(category);
      }

      for (final c in _rateControllers.values) {
        c.dispose();
      }
      _rateControllers.clear();

      final rows = grouped.entries
          .map(
            (e) => _HsnGstRow(
              hsnCode: e.key,
              categories: e.value..sort((a, b) => a.name.compareTo(b.name)),
            ),
          )
          .toList()
        ..sort((a, b) => a.hsnCode.compareTo(b.hsnCode));

      for (final row in rows) {
        _rateControllers[row.hsnCode] = TextEditingController(
          text: _formatRate(row.displayRate),
        );
      }

      if (!mounted) return;
      setState(() {
        _rows = rows;
        _filteredRows = rows;
        _isLoading = false;
      });
      _applySearch();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error loading HSN/GST data: $e';
        _isLoading = false;
      });
    }
  }

  void _applySearch() {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _filteredRows = _rows);
      return;
    }

    setState(() {
      _filteredRows = _rows.where((row) {
        if (row.hsnCode.contains(q)) return true;
        return row.categories.any((c) {
          return c.name.toLowerCase().contains(q) ||
              c.code.toLowerCase().contains(q);
        });
      }).toList();
    });
  }

  String _formatRate(double rate) {
    if (rate == rate.roundToDouble()) return rate.toStringAsFixed(0);
    return rate.toStringAsFixed(2);
  }

  Future<void> _commitBatchOps(
    List<void Function(WriteBatch batch)> ops,
  ) async {
    const batchLimit = 400;
    var batch = _firestore.batch();
    var count = 0;

    Future<void> flush() async {
      if (count == 0) return;
      await batch.commit();
      batch = _firestore.batch();
      count = 0;
    }

    for (final op in ops) {
      op(batch);
      count++;
      if (count >= batchLimit) {
        await flush();
      }
    }
    await flush();
  }

  /// For one user: update categories (code/docId match) and items (category_code match).
  Future<({int categories, int items})> _updateUserTaxForCodes({
    required String userDocId,
    required Set<String> categoryCodes,
    required double newTax,
    required String updatedAtIso,
  }) async {
    if (categoryCodes.isEmpty) return (categories: 0, items: 0);

    final userRef = _firestore.collection('users').doc(userDocId);
    final categoriesRef = userRef.collection('categories');
    final itemsRef = userRef.collection('items');

    // Categories: match by `code` field OR document id.
    final categoriesSnap = await categoriesRef.get();
    final categoryRefs = <String, DocumentReference>{};

    for (final doc in categoriesSnap.docs) {
      final data = doc.data();
      final fieldCode = _normCode(data['code']);
      final docIdCode = _normCode(doc.id);
      final matches =
          (fieldCode.isNotEmpty && categoryCodes.contains(fieldCode)) ||
              categoryCodes.contains(docIdCode);
      if (!matches) continue;
      categoryRefs[doc.reference.path] = doc.reference;
    }

    // Direct doc-id lookups for any missing codes.
    for (final code in categoryCodes) {
      final direct = await categoriesRef.doc(code).get();
      if (direct.exists) {
        categoryRefs[direct.reference.path] = direct.reference;
      }
    }

    if (categoryRefs.isNotEmpty) {
      await _commitBatchOps([
        for (final ref in categoryRefs.values)
          (batch) => batch.set(
                ref,
                {
                  'tax_percentage': newTax,
                  'updated_at': updatedAtIso,
                },
                SetOptions(merge: true),
              ),
      ]);
    }

    // Items: query by category_code for each selected code.
    final itemRefs = <String, DocumentReference>{};

    for (final code in categoryCodes) {
      try {
        final byField =
            await itemsRef.where('category_code', isEqualTo: code).get();
        for (final doc in byField.docs) {
          itemRefs[doc.reference.path] = doc.reference;
        }
      } catch (e) {
        debugPrint(
          'items where category_code=$code failed for $userDocId: $e',
        );
      }
    }

    // Fallback scan if categories matched but item queries returned nothing.
    if (itemRefs.isEmpty && categoryRefs.isNotEmpty) {
      final allItems = await itemsRef.get();
      for (final doc in allItems.docs) {
        final data = doc.data();
        final itemCat = _normCode(
          data['category_code'] ?? data['categoryCode'],
        );
        if (itemCat.isNotEmpty && categoryCodes.contains(itemCat)) {
          itemRefs[doc.reference.path] = doc.reference;
        }
      }
    }

    if (itemRefs.isNotEmpty) {
      await _commitBatchOps([
        for (final ref in itemRefs.values)
          (batch) => batch.set(
                ref,
                {
                  'tax_perc': newTax,
                  'updated_at': updatedAtIso,
                },
                SetOptions(merge: true),
              ),
      ]);
    }

    debugPrint(
      'User $userDocId: categories=${categoryRefs.length}, '
      'items=${itemRefs.length}, codes=${categoryCodes.join(',')}',
    );

    return (categories: categoryRefs.length, items: itemRefs.length);
  }

  Future<void> _updateGstForRow(_HsnGstRow row) async {
    final controller = _rateControllers[row.hsnCode];
    if (controller == null) return;

    final newTax = double.tryParse(controller.text.trim());
    if (newTax == null || newTax < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid GST rate'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final categoryCodes = row.categories
        .map((c) => c.code.trim())
        .where((c) => c.isNotEmpty)
        .toSet();

    if (categoryCodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No category codes to update'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Update GST for HSN ${row.hsnCode}'),
        content: Text(
          'Set GST to ${_formatRate(newTax)}% for ${categoryCodes.length} '
          'categor${categoryCodes.length == 1 ? 'y' : 'ies'} for this user only.\n\n'
          'Codes: ${categoryCodes.join(', ')}\n\n'
          'This updates:\n'
          '• categories.tax_percentage where code matches\n'
          '• items.tax_perc where category_code matches\n'
          '• updated_at on both',
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
            child: const Text('Update this user'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() {
      _updatingHsn = row.hsnCode;
      _progressDone = 0;
      _progressTotal = 1;
      _progressStatus = 'Updating…';
      _progressDetail = 'Resolving user document';
      _liveCategoriesUpdated = 0;
      _liveItemsUpdated = 0;
    });

    try {
      final userDocumentId = await _resolveUserDocumentId();
      if (userDocumentId == null) {
        if (!mounted) return;
        setState(() {
          _progressStatus = 'Failed';
          _progressDetail = 'User document not found';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User document not found'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      if (!mounted) return;
      setState(() {
        _progressDetail = 'Updating categories and items…';
      });

      final updatedAtIso = DateTime.now().toIso8601String();
      final result = await _updateUserTaxForCodes(
        userDocId: userDocumentId,
        categoryCodes: categoryCodes,
        newTax: newTax,
        updatedAtIso: updatedAtIso,
      );

      if (!mounted) return;
      setState(() {
        _progressDone = 1;
        _progressStatus = 'Completed';
        _progressDetail =
            'Updated ${result.categories} categories and ${result.items} items';
        _liveCategoriesUpdated = result.categories;
        _liveItemsUpdated = result.items;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'HSN ${row.hsnCode}: updated ${result.categories} categor'
            '${result.categories == 1 ? 'y' : 'ies'} and ${result.items} item'
            '${result.items == 1 ? '' : 's'} for this user',
          ),
          backgroundColor:
              result.categories == 0 && result.items == 0
                  ? Colors.orange
                  : Colors.green,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _progressStatus = 'Failed';
        _progressDetail = e.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update GST: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _updatingHsn = null;
          _progressStatus = '';
          _progressDetail = '';
          _progressDone = 0;
          _progressTotal = 0;
          _liveCategoriesUpdated = 0;
          _liveItemsUpdated = 0;
        });
      }
    }
  }

  void _showCategoryDetails(_HsnGstRow row) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Categories for HSN ${row.hsnCode}'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: row.categories.map((c) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${c.name} (${c.code}) — GST ${_formatRate(c.taxPercentage)}%',
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressPanel() {
    final progress = _progressTotal <= 0
        ? null
        : (_progressDone / _progressTotal).clamp(0.0, 1.0);
    final percent = progress == null ? null : (progress * 100).round();
    final isFailed = _progressStatus.toLowerCase().startsWith('failed');
    final isDone = _progressStatus.toLowerCase().startsWith('completed');
    final color = isFailed
        ? AppColors.primaryRed
        : isDone
            ? AppColors.successGreen
            : AppColors.primaryGreen;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: isDone || isFailed
                    ? Icon(
                        isFailed ? Icons.error_outline : Icons.check_circle,
                        size: 16,
                        color: color,
                      )
                    : CircularProgressIndicator(
                        strokeWidth: 2,
                        color: color,
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'STATUS: ${_progressStatus.toUpperCase()}',
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
              if (percent != null)
                Text(
                  '$percent%',
                  style: TextStyle(
                    fontSize: 13,
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
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.white,
              color: color,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _progressDetail.isEmpty ? 'Working…' : _progressDetail,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryText,
            ),
          ),
          if (_updatingHsn != null) ...[
            const SizedBox(height: 4),
            Text(
              'HSN $_updatingHsn',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statChip('Step', '$_progressDone/$_progressTotal', color),
              _statChip(
                'Categories',
                '$_liveCategoriesUpdated',
                AppColors.primaryGreen,
              ),
              _statChip('Items', '$_liveItemsUpdated', AppColors.primaryGreen),
            ],
          ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HSN & GST Rates'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _isLoading || _updatingHsn != null ? null : _loadData,
          ),
        ],
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
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadData,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: TextField(
                        controller: _searchController,
                        enabled: _updatingHsn == null,
                        decoration: InputDecoration(
                          hintText: 'Search HSN, category name, or code',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          isDense: true,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${_filteredRows.length} unique 6-digit HSN code'
                          '${_filteredRows.length == 1 ? '' : 's'}'
                          ' (updates apply to this user only)',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ),
                    ),
                    if (_updatingHsn != null || _progressStatus.isNotEmpty)
                      _buildProgressPanel(),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _filteredRows.isEmpty
                          ? const Center(
                              child: Text('No 6-digit HSN codes found'),
                            )
                          : SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SingleChildScrollView(
                                child: DataTable(
                                  headingRowColor: WidgetStateProperty.all(
                                    Colors.grey.shade100,
                                  ),
                                  columns: const [
                                    DataColumn(label: Text('HSN Code')),
                                    DataColumn(label: Text('GST Rate (%)')),
                                    DataColumn(label: Text('Categories')),
                                    DataColumn(label: Text('Action')),
                                  ],
                                  rows: _filteredRows.map((row) {
                                    final controller =
                                        _rateControllers[row.hsnCode]!;
                                    final isUpdating =
                                        _updatingHsn == row.hsnCode;

                                    return DataRow(
                                      cells: [
                                        DataCell(Text(row.hsnCode)),
                                        DataCell(
                                          SizedBox(
                                            width: 100,
                                            child: TextField(
                                              controller: controller,
                                              enabled: _updatingHsn == null,
                                              keyboardType:
                                                  const TextInputType
                                                      .numberWithOptions(
                                                decimal: true,
                                              ),
                                              decoration: InputDecoration(
                                                isDense: true,
                                                border:
                                                    const OutlineInputBorder(),
                                                hintText: _formatRate(
                                                  row.displayRate,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          InkWell(
                                            onTap: () =>
                                                _showCategoryDetails(row),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Text(row.categorySummary),
                                                if (row.hasMixedRates)
                                                  Text(
                                                    'Mixed GST rates',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color:
                                                          Colors.orange[800],
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          isUpdating
                                              ? const SizedBox(
                                                  width: 24,
                                                  height: 24,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  ),
                                                )
                                              : TextButton(
                                                  onPressed: _updatingHsn !=
                                                          null
                                                      ? null
                                                      : () =>
                                                          _updateGstForRow(row),
                                                  child: const Text(
                                                    'Update this user',
                                                  ),
                                                ),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }
}
