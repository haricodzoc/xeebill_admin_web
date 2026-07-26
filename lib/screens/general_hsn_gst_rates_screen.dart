import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:xeebill_web/models/general_category_model.dart';
import 'package:xeebill_web/models/subcategory_model.dart';
import 'package:xeebill_web/utils/app_colors.dart';

class _SubcategoryRef {
  final String generalCategoryDocId;
  final String generalCategoryCode;
  final String generalCategoryName;
  final String subcategoryCode;
  final String subcategoryName;
  final double gstRate;

  const _SubcategoryRef({
    required this.generalCategoryDocId,
    required this.generalCategoryCode,
    required this.generalCategoryName,
    required this.subcategoryCode,
    required this.subcategoryName,
    required this.gstRate,
  });
}

class _GeneralHsnGstRow {
  final String hsnCode;
  final List<_SubcategoryRef> subcategories;

  const _GeneralHsnGstRow({
    required this.hsnCode,
    required this.subcategories,
  });

  double get displayRate =>
      subcategories.isEmpty ? 0 : subcategories.first.gstRate;

  bool get hasMixedRates {
    if (subcategories.length <= 1) return false;
    final first = subcategories.first.gstRate;
    return subcategories.any((s) => s.gstRate != first);
  }

  String get summary {
    if (subcategories.length == 1) {
      final s = subcategories.first;
      return '${s.subcategoryName} (${s.subcategoryCode})';
    }
    return '${subcategories.length} subcategories';
  }
}

class GeneralHsnGstRatesScreen extends StatefulWidget {
  const GeneralHsnGstRatesScreen({super.key});

  @override
  State<GeneralHsnGstRatesScreen> createState() =>
      _GeneralHsnGstRatesScreenState();
}

class _GeneralHsnGstRatesScreenState extends State<GeneralHsnGstRatesScreen> {
  static const int _pageSize = 20;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;
  List<GeneralCategory> _categories = [];
  List<_GeneralHsnGstRow> _rows = [];
  List<_GeneralHsnGstRow> _filteredRows = [];
  final Map<String, TextEditingController> _rateControllers = {};
  String? _updatingHsn;
  int _currentPage = 0;

  int _progressDone = 0;
  int _progressTotal = 0;
  String _progressStatus = '';
  String _progressDetail = '';
  int _liveGeneralSubsUpdated = 0;
  int _liveCategoriesUpdated = 0;
  int _liveItemsUpdated = 0;
  int _liveUsersTouched = 0;

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

  String? _normalizeSixDigitHsn(String? raw) {
    if (raw == null) return null;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 6) return null;
    return digits;
  }

  String _formatRate(double rate) {
    if (rate == rate.roundToDouble()) return rate.toStringAsFixed(0);
    return rate.toStringAsFixed(2);
  }

  int get _totalPages {
    if (_filteredRows.isEmpty) return 1;
    return (_filteredRows.length / _pageSize).ceil();
  }

  List<_GeneralHsnGstRow> get _pagedRows {
    if (_filteredRows.isEmpty) return const [];
    final safePage = _currentPage.clamp(0, _totalPages - 1);
    final start = safePage * _pageSize;
    final end = (start + _pageSize).clamp(0, _filteredRows.length);
    return _filteredRows.sublist(start, end);
  }

  void _goToPage(int page) {
    final target = page.clamp(0, _totalPages - 1);
    if (target == _currentPage) return;
    setState(() => _currentPage = target);
  }

  List<_GeneralHsnGstRow> _buildRows(List<GeneralCategory> categories) {
    final grouped = <String, List<_SubcategoryRef>>{};

    for (final category in categories) {
      for (final sub in category.subcategories) {
        final hsn = _normalizeSixDigitHsn(sub.hsnCode);
        if (hsn == null) continue;

        grouped.putIfAbsent(hsn, () => []).add(
              _SubcategoryRef(
                generalCategoryDocId: category.id,
                generalCategoryCode: category.code,
                generalCategoryName: category.categoryName,
                subcategoryCode: sub.code,
                subcategoryName: sub.name,
                gstRate: sub.gstRate ?? 0,
              ),
            );
      }
    }

    return grouped.entries
        .map(
          (e) => _GeneralHsnGstRow(
            hsnCode: e.key,
            subcategories: e.value
              ..sort((a, b) => a.subcategoryCode.compareTo(b.subcategoryCode)),
          ),
        )
        .toList()
      ..sort((a, b) => a.hsnCode.compareTo(b.hsnCode));
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final snap = await _firestore.collection('general_categories').get();
      final categories = snap.docs
          .map(GeneralCategory.fromFirestore)
          .toList()
        ..sort((a, b) => a.categoryName.compareTo(b.categoryName));

      await GeneralCategory.attachSubcategoriesFromCollection(categories);

      final rows = _buildRows(categories);

      for (final c in _rateControllers.values) {
        c.dispose();
      }
      _rateControllers.clear();
      for (final row in rows) {
        _rateControllers[row.hsnCode] = TextEditingController(
          text: _formatRate(row.displayRate),
        );
      }

      if (!mounted) return;
      setState(() {
        _categories = categories;
        _rows = rows;
        _filteredRows = rows;
        _currentPage = 0;
        _isLoading = false;
      });
      _applySearch();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error loading general categories: $e';
        _isLoading = false;
      });
    }
  }

  void _applySearch() {
    final q = _searchController.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filteredRows = _rows;
      } else {
        _filteredRows = _rows.where((row) {
          if (row.hsnCode.contains(q)) return true;
          return row.subcategories.any((s) {
            return s.subcategoryCode.toLowerCase().contains(q) ||
                s.subcategoryName.toLowerCase().contains(q) ||
                s.generalCategoryName.toLowerCase().contains(q) ||
                s.generalCategoryCode.toLowerCase().contains(q);
          });
        }).toList();
      }
      _currentPage = 0;
    });
  }

  Widget _buildPaginationBar() {
    if (_filteredRows.isEmpty) return const SizedBox.shrink();

    final total = _filteredRows.length;
    final safePage = _currentPage.clamp(0, _totalPages - 1);
    final start = safePage * _pageSize + 1;
    final end = ((safePage + 1) * _pageSize).clamp(0, total);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          Text(
            'Showing $start–$end of $total',
            style: TextStyle(color: Colors.grey[700], fontSize: 13),
          ),
          const Spacer(),
          Text(
            'Page ${safePage + 1} of $_totalPages',
            style: TextStyle(color: Colors.grey[700], fontSize: 13),
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: 'Previous page',
            onPressed: safePage > 0 ? () => _goToPage(safePage - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: 'Next page',
            onPressed:
                safePage < _totalPages - 1 ? () => _goToPage(safePage + 1) : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  String _normCode(dynamic raw) => (raw ?? '').toString().trim();

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
      if (count >= batchLimit) await flush();
    }
    await flush();
  }

  Future<int> _updateGeneralSubcategories({
    required String hsnCode,
    required List<String> targetCodes,
    required double newRate,
    required String updatedAtIso,
  }) async {
    var updatedSubs = 0;
    const chunkSize = 10;
    final existingById = <String, DocumentSnapshot<Map<String, dynamic>>>{};

    for (var i = 0; i < targetCodes.length; i += chunkSize) {
      final chunk = targetCodes.skip(i).take(chunkSize).toList();
      final snap = await _firestore
          .collection('general_sub_categories')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        existingById[doc.id] = doc;
      }
    }

    final ops = <void Function(WriteBatch batch)>[];
    for (final code in targetCodes) {
      final doc = existingById[code];
      if (doc == null || !doc.exists) continue;

      final data = doc.data() ?? {};
      final hsn = _normalizeSixDigitHsn(data['hsn_code']?.toString());
      if (hsn != hsnCode) continue;

      ops.add(
        (batch) => batch.set(
              doc.reference,
              {
                'gst_rate': newRate,
                'updated_at': updatedAtIso,
              },
              SetOptions(merge: true),
            ),
      );
      updatedSubs++;
    }

    await _commitBatchOps(ops);
    return updatedSubs;
  }

  /// Per user: categories.code / items.category_code match selected subcategory codes.
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

    return (categories: categoryRefs.length, items: itemRefs.length);
  }

  Future<void> _updateGstForRow(_GeneralHsnGstRow row) async {
    final controller = _rateControllers[row.hsnCode];
    if (controller == null) return;

    final newRate = double.tryParse(controller.text.trim());
    if (newRate == null || newRate < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid GST rate'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final targetCodes = row.subcategories
        .map((s) => s.subcategoryCode.trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();
    final categoryCodes = targetCodes.toSet();

    if (categoryCodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No subcategory codes to update'),
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
          'Set GST to ${_formatRate(newRate)}% for ${categoryCodes.length} '
          'subcategor${categoryCodes.length == 1 ? 'y' : 'ies'}.\n\n'
          'This updates:\n'
          '• general_sub_categories.gst_rate\n'
          '• ALL users\' categories.tax_percentage where code matches\n'
          '• ALL users\' items.tax_perc where category_code matches',
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
            child: const Text('Update all users'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() {
      _updatingHsn = row.hsnCode;
      _progressDone = 0;
      _progressTotal = 0;
      _progressStatus = 'Updating general…';
      _progressDetail = 'Writing general_sub_categories';
      _liveGeneralSubsUpdated = 0;
      _liveCategoriesUpdated = 0;
      _liveItemsUpdated = 0;
      _liveUsersTouched = 0;
    });

    try {
      final updatedAtIso = DateTime.now().toIso8601String();

      final updatedSubs = await _updateGeneralSubcategories(
        hsnCode: row.hsnCode,
        targetCodes: targetCodes,
        newRate: newRate,
        updatedAtIso: updatedAtIso,
      );

      if (!mounted) return;
      setState(() {
        _liveGeneralSubsUpdated = updatedSubs;
        _progressStatus = 'Loading users…';
        _progressDetail = 'Fetching all users';
      });

      final usersSnap = await _firestore.collection('users').get();
      final userDocs = usersSnap.docs;

      var categoriesUpdated = 0;
      var itemsUpdated = 0;
      var usersTouched = 0;
      var userFailures = 0;

      if (!mounted) return;
      setState(() {
        _progressTotal = userDocs.length;
        _progressDone = 0;
        _progressStatus = 'Updating all users…';
        _progressDetail = '0 of ${userDocs.length} users';
      });

      for (var i = 0; i < userDocs.length; i++) {
        final userDoc = userDocs[i];
        final userLabel = (userDoc.data()['name'] ??
                userDoc.data()['email'] ??
                userDoc.id)
            .toString();

        if (!mounted) return;
        setState(() {
          _progressDone = i;
          _progressStatus = 'In progress';
          _progressDetail = 'User ${i + 1}/${userDocs.length}: $userLabel';
        });

        try {
          final result = await _updateUserTaxForCodes(
            userDocId: userDoc.id,
            categoryCodes: categoryCodes,
            newTax: newRate,
            updatedAtIso: updatedAtIso,
          );
          categoriesUpdated += result.categories;
          itemsUpdated += result.items;
          if (result.categories > 0 || result.items > 0) {
            usersTouched++;
          }
        } catch (e) {
          userFailures++;
          debugPrint('Failed updating user ${userDoc.id}: $e');
        }

        if (!mounted) return;
        setState(() {
          _progressDone = i + 1;
          _liveCategoriesUpdated = categoriesUpdated;
          _liveItemsUpdated = itemsUpdated;
          _liveUsersTouched = usersTouched;
          _progressDetail =
              'User ${i + 1}/${userDocs.length}: $userLabel'
              '${userFailures > 0 ? '  ·  $userFailures failed' : ''}';
        });
      }

      if (!mounted) return;
      setState(() {
        _progressStatus =
            userFailures > 0 ? 'Completed with errors' : 'Completed';
        _progressDetail =
            'General: $updatedSubs · Categories: $categoriesUpdated · '
            'Items: $itemsUpdated · Users: $usersTouched'
            '${userFailures > 0 ? ' ($userFailures failed)' : ''}';
        _progressDone = _progressTotal;
        _liveGeneralSubsUpdated = updatedSubs;
        _liveCategoriesUpdated = categoriesUpdated;
        _liveItemsUpdated = itemsUpdated;
        _liveUsersTouched = usersTouched;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'HSN ${row.hsnCode}: general $updatedSubs, '
            '$categoriesUpdated categories, $itemsUpdated items '
            'across $usersTouched users'
            '${userFailures > 0 ? ' ($userFailures failed)' : ''}',
          ),
          backgroundColor: userFailures > 0 ? Colors.orange : Colors.green,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
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
          _liveGeneralSubsUpdated = 0;
          _liveCategoriesUpdated = 0;
          _liveItemsUpdated = 0;
          _liveUsersTouched = 0;
        });
      }
    }
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
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statChip('Users', '$_progressDone/$_progressTotal', color),
              _statChip(
                'General',
                '$_liveGeneralSubsUpdated',
                AppColors.primaryGreen,
              ),
              _statChip(
                'Categories',
                '$_liveCategoriesUpdated',
                AppColors.primaryGreen,
              ),
              _statChip('Items', '$_liveItemsUpdated', AppColors.primaryGreen),
              _statChip('Touched', '$_liveUsersTouched', AppColors.primaryGrey),
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

  void _showSubcategoryDetails(_GeneralHsnGstRow row) {
    final groupedByGeneralCategory = <String, List<_SubcategoryRef>>{};
    for (final ref in row.subcategories) {
      groupedByGeneralCategory
          .putIfAbsent(ref.generalCategoryDocId, () => [])
          .add(ref);
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('HSN ${row.hsnCode} — Associated Categories'),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${row.subcategories.length} subcategor${row.subcategories.length == 1 ? 'y' : 'ies'} '
                  'across ${groupedByGeneralCategory.length} general '
                  'categor${groupedByGeneralCategory.length == 1 ? 'y' : 'ies'}',
                  style: TextStyle(color: Colors.grey[700], fontSize: 13),
                ),
                const SizedBox(height: 16),
                ...groupedByGeneralCategory.entries.map((entry) {
                  final refs = entry.value
                    ..sort((a, b) => a.subcategoryCode.compareTo(b.subcategoryCode));
                  final header = refs.first;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          header.generalCategoryName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'General category code: ${header.generalCategoryCode}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(
                              Colors.grey.shade50,
                            ),
                            columnSpacing: 20,
                            columns: const [
                              DataColumn(label: Text('Subcategory Code')),
                              DataColumn(label: Text('Name')),
                              DataColumn(label: Text('HSN')),
                              DataColumn(label: Text('Unit')),
                              DataColumn(label: Text('GST %')),
                              DataColumn(label: Text('Description')),
                            ],
                            rows: refs.map((ref) {
                              final sub = _findSubcategory(ref);
                              final description =
                                  (sub?.description ?? '').trim();

                              return DataRow(
                                cells: [
                                  DataCell(Text(ref.subcategoryCode)),
                                  DataCell(
                                    SizedBox(
                                      width: 140,
                                      child: Text(ref.subcategoryName),
                                    ),
                                  ),
                                  DataCell(Text(sub?.hsnCode ?? row.hsnCode)),
                                  DataCell(Text(sub?.unit ?? '—')),
                                  DataCell(
                                    Text(_formatRate(ref.gstRate)),
                                  ),
                                  DataCell(
                                    SizedBox(
                                      width: 220,
                                      child: Text(
                                        description.isEmpty ? '—' : description,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
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

  SubCategory? _findSubcategory(_SubcategoryRef ref) {
    for (final category in _categories) {
      if (category.id != ref.generalCategoryDocId) continue;
      for (final sub in category.subcategories) {
        if (sub.code.trim() == ref.subcategoryCode.trim()) {
          return sub;
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.backgroundGrey,
        title: const Text(
          'HSN & GST Rates',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: AppColors.primaryGreen),
            tooltip: 'Refresh',
            onPressed: _isLoading || _updatingHsn != null ? null : _loadData,
          ),
        ],
      ),
      backgroundColor: AppColors.backgroundGrey,
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
                          hintText:
                              'Search HSN, subcategory, or general category',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.white,
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
                          ' (updates apply to all users)',
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                child: Card(
                                  child: DataTable(
                                    headingRowColor: WidgetStateProperty.all(
                                      Colors.grey.shade100,
                                    ),
                                    columns: const [
                                      DataColumn(label: Text('HSN Code')),
                                      DataColumn(label: Text('GST Rate (%)')),
                                      DataColumn(label: Text('Subcategories')),
                                      DataColumn(label: Text('Details')),
                                      DataColumn(label: Text('Action')),
                                    ],
                                    rows: _pagedRows.map((row) {
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
                                                decoration:
                                                    const InputDecoration(
                                                  isDense: true,
                                                  border: OutlineInputBorder(),
                                                ),
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Text(row.summary),
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
                                          DataCell(
                                            IconButton(
                                              icon: Icon(
                                                Icons.visibility_outlined,
                                                color: AppColors.primaryGreen,
                                              ),
                                              tooltip: 'View category details',
                                              onPressed: () =>
                                                  _showSubcategoryDetails(row),
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
                                                    onPressed:
                                                        _updatingHsn != null
                                                            ? null
                                                            : () =>
                                                                _updateGstForRow(
                                                                  row,
                                                                ),
                                                    child: const Text(
                                                      'Update all users',
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
                    ),
                    _buildPaginationBar(),
                  ],
                ),
    );
  }
}
