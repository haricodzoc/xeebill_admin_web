import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:xeebill_web/models/general_category_model.dart';
import 'package:xeebill_web/models/subcategory_model.dart';
import 'package:xeebill_web/screens/add_subcategory_screen.dart';
import 'package:xeebill_web/screens/general_hsn_gst_rates_screen.dart';
import 'package:xeebill_web/screens/rate_tax_definition_screen.dart';
import 'package:xeebill_web/utils/app_colors.dart';
import 'package:xeebill_web/utils/constants.dart';
import 'package:xeebill_web/utils/functions.dart';

class GeneralCategoryScreen extends StatefulWidget {
  const GeneralCategoryScreen({super.key});

  @override
  State<GeneralCategoryScreen> createState() => _GeneralCategoryScreenState();
}

class _GeneralCategoryScreenState extends State<GeneralCategoryScreen> {
  List<GeneralCategory> _categories = [];
  List<GeneralCategory> _filteredCategories = [];
  bool _isLoading = true;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String? _highlightCategoryCode;
  String? _highlightSubcategoryCode;
  Timer? _clearHighlightTimer;
  final ScrollController _categoryListScrollController = ScrollController();

  String _normalizeForSearch(String input) {
    final lower = input.trim().toLowerCase();
    final noSpace = lower.replaceAll(RegExp(r'[\\s\\u00A0]+'), '');
    return noSpace.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// Builds the filtered list for a non-empty normalized query (same rules as search UI).
  List<GeneralCategory> _filterCategoriesByNormalizedQuery(
    List<GeneralCategory> source,
    String q,
  ) {
    final List<GeneralCategory> results = [];

    for (final category in source) {
      final catName = _normalizeForSearch(category.categoryName);
      final catCode = _normalizeForSearch(category.code);

      final matchesCategory = catName.contains(q) || catCode.contains(q);

      final matchingSubs = category.subcategories.where((sub) {
        final name = _normalizeForSearch(sub.name);
        final code = _normalizeForSearch(sub.code);
        final hsn = _normalizeForSearch(sub.hsnCode ?? '');
        final desc = _normalizeForSearch(sub.description ?? '');
        return name.contains(q) ||
            code.contains(q) ||
            hsn.contains(q) ||
            desc.contains(q);
      }).toList();

      if (matchesCategory) {
        final copy = GeneralCategory(
          id: category.id,
          code: category.code,
          categoryName: category.categoryName,
          subcategories: List<SubCategory>.from(category.subcategories),
          isExpanded: true,
          isAllSelected: category.isAllSelected,
        );
        results.add(copy);
      } else if (matchingSubs.isNotEmpty) {
        final copy = GeneralCategory(
          id: category.id,
          code: category.code,
          categoryName: category.categoryName,
          subcategories: matchingSubs,
          isExpanded: true,
          isAllSelected: category.isAllSelected,
        );
        results.add(copy);
      }
    }

    return results;
  }

  @override
  void initState() {
    super.initState();
    _loadGeneralCategories();
  }

  @override
  void dispose() {
    _clearHighlightTimer?.cancel();
    _categoryListScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _scheduleClearReturnHighlight() {
    _clearHighlightTimer?.cancel();
    _clearHighlightTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() {
        _highlightCategoryCode = null;
        _highlightSubcategoryCode = null;
      });
    });
  }

  static String _normCatCode(String? s) => (s ?? '').trim();

  static String _normSubCode(String? s) => (s ?? '').trim().toLowerCase();

  Future<void> _loadGeneralCategories({
    String? expandCategoryCode,
    String? highlightCategoryCode,
    String? highlightSubcategoryCode,
    double? restoreScrollOffset,
  }) async {
    try {
      setState(() {
        _isLoading = true;
      });

      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('general_categories')
          .get();

      List<GeneralCategory> categories = querySnapshot.docs
          .map((doc) => GeneralCategory.fromFirestore(doc))
          .toList();

      // Sort categories alphabetically by category name
      categories.sort(
        (a, b) => a.categoryName.toLowerCase().compareTo(
          b.categoryName.toLowerCase(),
        ),
      );

      // Load subcategories from general_sub_categories (by gen_cat_code)
      await GeneralCategory.attachSubcategoriesFromCollection(categories);

      final expandNorm = _normCatCode(expandCategoryCode);
      final highlightCatNorm = _normCatCode(highlightCategoryCode);
      final highlightSubNorm = highlightSubcategoryCode == null
          ? ''
          : _normSubCode(highlightSubcategoryCode);

      final searchQ = _normalizeForSearch(_searchController.text);

      setState(() {
        _categories = categories;
        if (expandNorm.isNotEmpty) {
          for (final c in _categories) {
            c.isExpanded = _normCatCode(c.code) == expandNorm;
          }
        }
        if (searchQ.isEmpty) {
          _filteredCategories = categories;
          _isSearching = false;
        } else {
          _filteredCategories =
              _filterCategoriesByNormalizedQuery(categories, searchQ);
          _isSearching = true;
        }
        _isLoading = false;
        _highlightCategoryCode =
            highlightCatNorm.isEmpty ? null : highlightCatNorm;
        _highlightSubcategoryCode =
            highlightSubNorm.isEmpty ? null : highlightSubNorm;
      });

      if (highlightSubNorm.isNotEmpty || restoreScrollOffset != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (highlightSubNorm.isNotEmpty) {
            setState(() {});
          }
          void applyScroll() {
            if (!mounted ||
                restoreScrollOffset == null ||
                !_categoryListScrollController.hasClients) {
              return;
            }
            final maxScroll =
                _categoryListScrollController.position.maxScrollExtent;
            final target = restoreScrollOffset.clamp(0.0, maxScroll);
            _categoryListScrollController.jumpTo(target);
          }

          applyScroll();
          if (restoreScrollOffset != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              applyScroll();
            });
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading categories: $e');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading categories: $e')));
      }
    }
  }

  void _performSearch(String query) {
    final q = _normalizeForSearch(query);
    if (q.isEmpty) {
      setState(() {
        _filteredCategories = _categories;
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _filteredCategories = _filterCategoriesByNormalizedQuery(_categories, q);
      _isSearching = true;
    });
  }

  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _filteredCategories = _categories;
      _isSearching = false;
    });
  }

  void _toggleCategoryExpansion(int index) {
    setState(() {
      final cat = _filteredCategories[index];
      cat.isExpanded = !cat.isExpanded;

      // Also update in original categories to maintain state
      final original = _categories.firstWhere(
        (c) => c.code == cat.code,
        orElse: () => cat,
      );
      original.isExpanded = cat.isExpanded;
    });
  }

  double _categoryListScrollOffsetOrZero() {
    if (!_categoryListScrollController.hasClients) return 0;
    return _categoryListScrollController.offset;
  }

  List<Map<String, dynamic>> _parseGeneralSubCategoryMapsFromJson(
    String raw, {
    required String selectedCategoryCode,
  }) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('JSON cannot be empty');
    }

    final categoryCode = selectedCategoryCode.trim();
    if (categoryCode.isEmpty) {
      throw const FormatException('Selected category code is empty');
    }
    final requiredPrefix = '$categoryCode-';

    final decoded = jsonDecode(trimmed);
    if (decoded is! List) {
      throw const FormatException(
        'JSON must be an array of subcategory objects',
      );
    }

    final parsed = <Map<String, dynamic>>[];
    final seenCodes = <String>{};

    for (var i = 0; i < decoded.length; i++) {
      final item = decoded[i];
      if (item is! Map) {
        throw FormatException('Item at index $i must be a JSON object');
      }

      final map = Map<String, dynamic>.from(item);
      final code = (map['code'] ?? '').toString().trim();
      final name = (map['name'] ?? '').toString().trim();

      if (code.isEmpty || name.isEmpty) {
        throw FormatException(
          'Item at index $i must include non-empty "code" and "name"',
        );
      }
      if (!code.startsWith(requiredPrefix)) {
        throw FormatException(
          'Item at index $i: code "$code" must start with "$requiredPrefix" '
          '(selected category code is $categoryCode). '
          'Example: ${requiredPrefix}01',
        );
      }
      if (code == requiredPrefix || code == categoryCode) {
        throw FormatException(
          'Item at index $i: code "$code" must include a suffix after '
          '"$requiredPrefix" (e.g. ${requiredPrefix}01)',
        );
      }
      if (seenCodes.contains(code)) {
        throw FormatException('Duplicate subcategory code "$code" in JSON');
      }
      seenCodes.add(code);

      // Store attributes as a JSON string.
      String attributesJson = '';
      final rawAttributes = map['attributes'];
      if (rawAttributes is String) {
        attributesJson = rawAttributes;
      } else if (rawAttributes is Map || rawAttributes is List) {
        attributesJson = jsonEncode(rawAttributes);
      } else if (rawAttributes != null) {
        attributesJson = rawAttributes.toString();
      }

      String attributeTypes = '';
      final rawAttributeTypes = map['attribute_types'];
      if (rawAttributeTypes is String) {
        attributeTypes = rawAttributeTypes;
      } else if (rawAttributeTypes is Map || rawAttributeTypes is List) {
        attributeTypes = jsonEncode(rawAttributeTypes);
      } else if (rawAttributeTypes != null) {
        attributeTypes = rawAttributeTypes.toString();
      }

      final gstRaw = map['gst_rate'];
      final gstRate = gstRaw is num
          ? gstRaw.toDouble()
          : double.tryParse(gstRaw?.toString() ?? '');

      parsed.add({
        'code': code,
        'name': name,
        'attributes': attributesJson,
        'attribute_types': attributeTypes,
        'hsn_code': (map['hsn_code'] ?? '').toString().trim(),
        'unit': (map['unit'] ?? 'Piece').toString().trim().isEmpty
            ? 'Piece'
            : (map['unit'] ?? 'Piece').toString().trim(),
        'description': (map['description'] ?? '').toString(),
        'gst_rate': gstRate,
      });
    }

    return parsed;
  }

  Future<void> _showImportSubcategoriesJsonDialog(int index) async {
    final category = _filteredCategories[index];
    final originalCategory = _categories.firstWhere(
      (c) => c.code == category.code,
      orElse: () => category,
    );
    final categoryCode = category.code.trim();
    final subcategoryCount = originalCategory.subcategories.length;
    final requiredPrefix = '$categoryCode-';
    final jsonController = TextEditingController();
    var isSubmitting = false;
    String? errorText;

    final exampleJson = '''[
  {
    "code": "${requiredPrefix}01",
    "name": "Example Item",
    "attributes": "{\\"Type\\":{\\"Fresh\\":false}}",
    "attribute_types": "",
    "hsn_code": "030695",
    "unit": "Packet",
    "description": "",
    "gst_rate": 5
  }
]''';

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: !isSubmitting,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Import subcategories — ${category.categoryName}'),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.55,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primaryGreen.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.primaryGreen.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Selected category code',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[700],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              categoryCode,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'monospace',
                                color: AppColors.primaryGreen,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              subcategoryCount == 1
                                  ? '1 subcategory currently in this category'
                                  : '$subcategoryCount subcategories currently in this category',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primaryText,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Hint: every subcategory "code" in the JSON must start with '
                              '"$requiredPrefix" (e.g. ${requiredPrefix}01, ${requiredPrefix}04).',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                color: AppColors.primaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Paste a JSON array. Each object is saved as a record in '
                        'general_sub_categories (document id = code).',
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: jsonController,
                        maxLines: 14,
                        minLines: 10,
                        enabled: !isSubmitting,
                        decoration: InputDecoration(
                          hintText: exampleJson,
                          border: const OutlineInputBorder(),
                          alignLabelWithHint: true,
                          errorText: errorText,
                        ),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDialogState(() {
                            isSubmitting = true;
                            errorText = null;
                          });

                          try {
                            final parsed = _parseGeneralSubCategoryMapsFromJson(
                              jsonController.text,
                              selectedCategoryCode: categoryCode,
                            );

                            // Check which codes already exist.
                            final existingDocs =
                                <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                            const chunkSize = 10;
                            for (var i = 0; i < parsed.length; i += chunkSize) {
                              final chunk = parsed
                                  .skip(i)
                                  .take(chunkSize)
                                  .map((e) => e['code'] as String)
                                  .toList();
                              final snap = await FirebaseFirestore.instance
                                  .collection('general_sub_categories')
                                  .where(FieldPath.documentId, whereIn: chunk)
                                  .get();
                              existingDocs.addAll(snap.docs);
                            }

                            final existingById = {
                              for (final doc in existingDocs) doc.id: doc,
                            };
                            final existingCodes = existingById.keys.toList()
                              ..sort();

                            if (existingCodes.isNotEmpty) {
                              if (!dialogContext.mounted) return;
                              final preview = existingCodes.take(8).join(', ');
                              final more = existingCodes.length > 8
                                  ? ' and ${existingCodes.length - 8} more'
                                  : '';
                              final replace = await showDialog<bool>(
                                context: dialogContext,
                                builder: (confirmCtx) => AlertDialog(
                                  title: const Text('Replace existing records?'),
                                  content: Text(
                                    '${existingCodes.length} subcategor'
                                    '${existingCodes.length == 1 ? 'y' : 'ies'} '
                                    'already exist in general_sub_categories:\n\n'
                                    '$preview$more\n\n'
                                    'Replace them with the imported values?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(confirmCtx, false),
                                      child: const Text('Cancel'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () =>
                                          Navigator.pop(confirmCtx, true),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.orange,
                                        foregroundColor: Colors.white,
                                      ),
                                      child: const Text('Replace'),
                                    ),
                                  ],
                                ),
                              );

                              if (replace != true) {
                                setDialogState(() => isSubmitting = false);
                                return;
                              }
                            }

                            final now = DateTime.now();
                            var createdCount = 0;
                            var replacedCount = 0;

                            // Firestore batch limit is 500.
                            const batchLimit = 400;
                            var batch = FirebaseFirestore.instance.batch();
                            var opsInBatch = 0;

                            Future<void> commitBatch() async {
                              if (opsInBatch == 0) return;
                              await batch.commit();
                              batch = FirebaseFirestore.instance.batch();
                              opsInBatch = 0;
                            }

                            for (final item in parsed) {
                              final code = item['code'] as String;
                              final ref = FirebaseFirestore.instance
                                  .collection('general_sub_categories')
                                  .doc(code);

                              final existing = existingById[code];
                              DateTime createdAt = now;
                              if (existing != null) {
                                final data = existing.data();
                                final rawCreated = data['created_at'];
                                if (rawCreated is Timestamp) {
                                  createdAt = rawCreated.toDate();
                                } else if (rawCreated is String) {
                                  createdAt =
                                      DateTime.tryParse(rawCreated) ?? now;
                                }
                                replacedCount++;
                              } else {
                                createdCount++;
                              }

                              batch.set(ref, {
                                'code': code,
                                'gen_cat_code': category.code,
                                'name': item['name'],
                                'attributes': item['attributes'],
                                'attribute_types': item['attribute_types'],
                                'hsn_code': item['hsn_code'],
                                'unit': item['unit'],
                                'description': item['description'],
                                'gst_rate': item['gst_rate'],
                                'remarks': <String, dynamic>{},
                                'created_at': createdAt.toIso8601String(),
                                'updated_at': now.toIso8601String(),
                              });
                              opsInBatch++;

                              if (opsInBatch >= batchLimit) {
                                await commitBatch();
                              }
                            }
                            await commitBatch();

                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();

                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Imported ${parsed.length} subcategor'
                                  '${parsed.length == 1 ? 'y' : 'ies'} '
                                  '($createdCount new, $replacedCount replaced)',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } on FormatException catch (e) {
                            setDialogState(() {
                              errorText = e.message;
                              isSubmitting = false;
                            });
                          } catch (e) {
                            setDialogState(() {
                              errorText = e.toString();
                              isSubmitting = false;
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Import'),
                ),
              ],
            );
          },
        );
      },
    );

    jsonController.dispose();
  }

  Future<void> _navigateToAddSubcategory(int index) async {
    final category = _filteredCategories[index];
    // Find the original category to get all subcategories
    final originalCategory = _categories.firstWhere(
      (c) => c.code == category.code,
      orElse: () => category,
    );
    final savedScroll = _categoryListScrollOffsetOrZero();
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddSubcategoryScreen(
          categoryCode: originalCategory.code,
          categoryName: originalCategory.categoryName,
          subcategories: originalCategory.subcategories,
        ),
      ),
    );

    if (result != null && result is List<SubCategory>) {
      final updated = result;
      final beforeCodes = originalCategory.subcategories
          .map((e) => e.code.trim())
          .toSet();
      String? newSubCode;
      for (final s in updated) {
        final c = s.code.trim();
        if (c.isNotEmpty && !beforeCodes.contains(c)) {
          newSubCode = c;
          break;
        }
      }
      await _loadGeneralCategories(
        expandCategoryCode: originalCategory.code,
        highlightCategoryCode:
            newSubCode != null ? originalCategory.code : null,
        highlightSubcategoryCode: newSubCode,
        restoreScrollOffset: savedScroll,
      );
      if (newSubCode != null) {
        _scheduleClearReturnHighlight();
      }
    }
  }

  Future<void> _navigateToEditSubcategory(
    int categoryIndex,
    int subcategoryIndex,
  ) async {
    final category = _filteredCategories[categoryIndex];
    final subcategory = category.subcategories[subcategoryIndex];

    // Find the original category to get all subcategories
    final originalCategory = _categories.firstWhere(
      (c) => c.code == category.code,
      orElse: () => category,
    );

    // Find the original subcategory
    final originalSubcategory = originalCategory.subcategories.firstWhere(
      (s) => s.code == subcategory.code,
      orElse: () => subcategory,
    );

    final catCode = originalCategory.code;
    final subCode = originalSubcategory.code.trim();
    final savedScroll = _categoryListScrollOffsetOrZero();

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddSubcategoryScreen(
          categoryCode: originalCategory.code,
          categoryName: originalCategory.categoryName,
          subcategories: originalCategory.subcategories,
          selectedSubcategory: originalSubcategory,
          isUpdate: true,
        ),
      ),
    );

    if (result != null && result is List<SubCategory>) {
      await _loadGeneralCategories(
        expandCategoryCode: catCode,
        highlightCategoryCode: catCode,
        highlightSubcategoryCode: subCode.isNotEmpty ? subCode : null,
        restoreScrollOffset: savedScroll,
      );
      if (subCode.isNotEmpty) {
        _scheduleClearReturnHighlight();
      }
    }
  }

  String _generateNextCategoryCode() {
    if (_categories.isEmpty) {
      return '000001';
    }

    // Extract numeric values from all category codes
    List<int> numericCodes = [];
    for (var category in _categories) {
      // Try to parse the code as a number (handles patterns like '000026', '000001')
      final numericValue = int.tryParse(category.code);
      if (numericValue != null) {
        numericCodes.add(numericValue);
      }
    }

    // If no numeric codes found, start from 1
    if (numericCodes.isEmpty) {
      return '000001';
    }

    // Find the maximum and add 1
    final maxCode = numericCodes.reduce((a, b) => a > b ? a : b);
    final nextCode = maxCode + 1;

    // Format as 6-digit zero-padded string
    return nextCode.toString().padLeft(6, '0');
  }

  Future<void> _addNewCategory() async {
    final nameController = TextEditingController();
    final codeController = TextEditingController(
      text: _generateNextCategoryCode(),
    );
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add New Category'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Category Name *',
                      border: OutlineInputBorder(),
                      hintText: 'e.g., Electronics',
                    ),
                    validator: (value) => value?.isEmpty ?? true
                        ? 'Category name is required'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: codeController,
                    decoration: const InputDecoration(
                      labelText: 'Category Code *',
                      border: OutlineInputBorder(),
                      hintText: 'e.g., 000001',
                      helperText: 'Auto-generated, can be modified',
                    ),
                    validator: (value) => value?.isEmpty ?? true
                        ? 'Category code is required'
                        : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  // Check if code already exists
                  final codeExists = _categories.any(
                    (cat) =>
                        cat.code.toLowerCase() ==
                        codeController.text.trim().toLowerCase(),
                  );

                  if (codeExists) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Category code already exists'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  // Create new category in Firestore
                  try {
                    await FirebaseFirestore.instance
                        .collection('general_categories')
                        .add({
                          'code': codeController.text.trim(),
                          'category_name': nameController.text.trim(),
                          'createdAt': DateTime.now(),
                          'updatedAt': DateTime.now(),
                        });

                    if (mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Category added successfully'),
                          backgroundColor: Colors.green,
                        ),
                      );
                      _loadGeneralCategories();
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error adding category: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
              ),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _addNewSubcategory() async {
    if (_categories.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No categories available')));
      return;
    }

    // Show dialog to select category
    GeneralCategory? selectedCategory = await showDialog<GeneralCategory>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Category'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                return ListTile(
                  title: Text(category.categoryName),
                  subtitle: Text(
                    '${category.subcategories.length} subcategories',
                  ),
                  onTap: () {
                    Navigator.of(context).pop(category);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    if (selectedCategory != null && mounted) {
      // Open add subcategory dialog or screen
      _openAddSubcategoryDialog(selectedCategory);
    }
  }

  Future<void> _openAddSubcategoryDialog(GeneralCategory category) async {
    // Create a simple dialog to add a new subcategory
    // You can replace this with a more sophisticated form
    final nameController = TextEditingController();
    final codeController = TextEditingController();
    final hsnCodeController = TextEditingController();
    final unitController = TextEditingController(text: 'Number');
    final gstRateController = TextEditingController();

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Add Subcategory to ${category.categoryName}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Subcategory Name *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: codeController,
                  decoration: const InputDecoration(
                    labelText: 'Subcategory Code *',
                    hintText: 'e.g., CAT-001',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: hsnCodeController,
                  decoration: const InputDecoration(
                    labelText: 'HSN Code',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: unitController,
                  decoration: const InputDecoration(
                    labelText: 'Unit',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: gstRateController,
                  decoration: const InputDecoration(
                    labelText: 'GST Rate (%)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isEmpty ||
                    codeController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Name and Code are required')),
                  );
                  return;
                }

                final newCode = codeController.text.trim();
                if (category.subcategories.any(
                  (s) => s.code.trim() == newCode,
                )) {
                  final existing = category.subcategories.firstWhere(
                    (s) => s.code.trim() == newCode,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Code "$newCode" is already used by "${existing.name}". '
                        'Use a unique code so an existing subcategory is not replaced.',
                      ),
                    ),
                  );
                  return;
                }

                // Create new subcategory in general_sub_categories
                SubCategory newSubcategory = SubCategory(
                  name: nameController.text,
                  code: newCode,
                  attributes: '',
                  attributeTypes: '',
                  hsnCode: hsnCodeController.text.isEmpty
                      ? null
                      : hsnCodeController.text,
                  unit: unitController.text.isEmpty
                      ? null
                      : unitController.text,
                  gstRate: gstRateController.text.isEmpty
                      ? null
                      : double.tryParse(gstRateController.text),
                );

                final saved =
                    await _upsertSubcategoryInCollection(
                      categoryCode: category.code,
                      subcategory: newSubcategory,
                    );
                if (!saved) return;

                if (mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Subcategory added successfully'),
                    ),
                  );
                  _loadGeneralCategories(); // Reload to refresh UI
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
              ),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _upsertSubcategoryInCollection({
    required String categoryCode,
    required SubCategory subcategory,
    String? previousCode,
  }) async {
    try {
      final code = subcategory.code.trim();
      if (code.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Subcategory code cannot be empty'),
            ),
          );
        }
        return false;
      }

      final now = DateTime.now().toIso8601String();
      final col = FirebaseFirestore.instance.collection('general_sub_categories');
      final oldCode = (previousCode ?? '').trim();

      if (oldCode.isNotEmpty && oldCode != code) {
        final oldRef = col.doc(oldCode);
        final oldSnap = await oldRef.get();
        String createdAt = now;
        Map<String, dynamic> remarks = {};
        if (oldSnap.exists) {
          final data = oldSnap.data() ?? {};
          final rawCreated = data['created_at'];
          if (rawCreated is Timestamp) {
            createdAt = rawCreated.toDate().toIso8601String();
          } else if (rawCreated is String && rawCreated.isNotEmpty) {
            createdAt = rawCreated;
          }
          final rawRemarks = data['remarks'];
          if (rawRemarks is Map) {
            remarks = Map<String, dynamic>.from(rawRemarks);
          }
          await oldRef.delete();
        }
        await col.doc(code).set(
              subcategory.toFirestoreMap(
                genCatCode: categoryCode,
                createdAt: createdAt,
                updatedAt: now,
                remarks: remarks,
              ),
            );
        return true;
      }

      final ref = col.doc(code);
      final existing = await ref.get();
      String createdAt = now;
      Map<String, dynamic> remarks = {};
      if (existing.exists) {
        final data = existing.data() ?? {};
        final rawCreated = data['created_at'];
        if (rawCreated is Timestamp) {
          createdAt = rawCreated.toDate().toIso8601String();
        } else if (rawCreated is String && rawCreated.isNotEmpty) {
          createdAt = rawCreated;
        }
        final rawRemarks = data['remarks'];
        if (rawRemarks is Map) {
          remarks = Map<String, dynamic>.from(rawRemarks);
        }
      }

      await ref.set(
        subcategory.toFirestoreMap(
          genCatCode: categoryCode,
          createdAt: createdAt,
          updatedAt: now,
          remarks: remarks,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('Error saving subcategory: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving subcategory: $e')),
        );
      }
      return false;
    }
  }

  Future<bool> _deleteSubcategoryFromCollection(String code) async {
    try {
      final trimmed = code.trim();
      if (trimmed.isEmpty) return false;
      await FirebaseFirestore.instance
          .collection('general_sub_categories')
          .doc(trimmed)
          .delete();
      return true;
    } catch (e) {
      debugPrint('Error deleting subcategory: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting subcategory: $e')),
        );
      }
      return false;
    }
  }

  Future<Map<String, dynamic>> checkSubcategoryCodeUniqueness() async {
    debugPrint(
      'Checking uniqueness of all subcategory codes in _categories...',
    );
    Map<String, List<Map<String, String>>> codeMap = {};
    bool allUnique = true;
    List<Map<String, dynamic>> duplicates = [];

    try {
      // Collect all subcategory codes from all categories
      for (var category in _categories) {
        final categoryCode = category.code;
        final categoryName = category.categoryName;
        final subcategories = category.subcategories;

        // Skip if no subcategories
        if (subcategories.isEmpty) continue;

        // Process each subcategory
        for (var subcat in subcategories) {
          final code = subcat.code.trim();
          final name = subcat.name.trim();

          // Skip empty codes
          if (code.isEmpty) continue;

          // Track subcategory code
          codeMap.putIfAbsent(code, () => []);
          codeMap[code]!.add({
            'category_code': categoryCode,
            'category_name': categoryName,
            'subcat_code': code,
            'subcat_name': name,
          });
        }
      }

      // Find duplicates (codes that appear more than once)
      codeMap.forEach((code, occurrences) {
        if (occurrences.length > 1) {
          allUnique = false;
          duplicates.add({
            'code': code,
            'count': occurrences.length,
            'occurrences': occurrences,
          });
        }
      });

      // Print results
      if (duplicates.isNotEmpty) {
        debugPrint('\n=== Duplicate Subcategory Codes Found ===');
        debugPrint('Total duplicate codes: ${duplicates.length}');
        for (var dup in duplicates) {
          debugPrint('Code: ${dup['code']} (${dup['count']} occurrences)');
          for (var occ in dup['occurrences']) {
            debugPrint(
              '  - ${occ['category_name']} (${occ['category_code']}) -> ${occ['subcat_name']} (${occ['subcat_code']})',
            );
          }
        }
      } else {
        debugPrint('\n=== All Subcategory Codes Are Unique ===');
        debugPrint('Total unique subcategory codes: ${codeMap.length}');
      }

      return {
        'allUnique': allUnique,
        'totalCodes': codeMap.length,
        'duplicateCount': duplicates.length,
        'duplicates': duplicates,
      };
    } catch (e, stack) {
      await logErrorToFile(e.toString(), stack);
      debugPrint('Error checking subcategory code uniqueness: $e');
      return {
        'allUnique': false,
        'totalCodes': 0,
        'duplicateCount': 0,
        'duplicates': [],
        'error': e.toString(),
      };
    }
  }

  Future<void> _checkDuplicateCodes() async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    // Call the check function
    final result = await checkSubcategoryCodeUniqueness();

    // Close loading dialog
    if (mounted) {
      Navigator.of(context).pop();
    }

    // Show results dialog
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(
                result['allUnique'] == true
                    ? Icons.check_circle
                    : Icons.warning,
                color: result['allUnique'] == true
                    ? Colors.green
                    : Colors.orange,
              ),
              const SizedBox(width: 8),
              Text(
                result['allUnique'] == true
                    ? 'All Codes Unique'
                    : 'Duplicate Codes Found',
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (result['error'] != null) ...[
                    Text(
                      'Error: ${result['error']}',
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    'Total unique codes: ${result['totalCodes']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Duplicate codes: ${result['duplicateCount']}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: result['duplicateCount'] > 0
                          ? Colors.orange
                          : Colors.green,
                    ),
                  ),
                  if (result['duplicates'] != null &&
                      (result['duplicates'] as List).isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    const Text(
                      'Duplicate Details:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...(result['duplicates'] as List).map((dup) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Code: ${dup['code']} (${dup['count']} occurrences)',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...(dup['occurrences'] as List).map((occ) {
                              return Padding(
                                padding: const EdgeInsets.only(
                                  left: 8,
                                  top: 4,
                                  bottom: 4,
                                ),
                                child: Text(
                                  '• ${occ['category_name']} (${occ['category_code']}) → ${occ['subcat_name']} (${occ['subcat_code']})',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _deleteSubcategory(
    int categoryIndex,
    int subcategoryIndex,
  ) async {
    final category = _filteredCategories[categoryIndex];
    final subcategory = category.subcategories[subcategoryIndex];

    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Subcategory'),
        content: Text('Are you sure you want to delete "${subcategory.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    try {
      final deleted =
          await _deleteSubcategoryFromCollection(subcategory.code);
      if (!deleted) return;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Subcategory deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadGeneralCategories(); // Reload to refresh UI
      }
    } catch (e) {
      debugPrint('Error deleting subcategory: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting subcategory: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.backgroundGrey,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            color: AppColors.primaryGreen,
            size: 18,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: Text(
          'General Categories',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryText,
          ),
        ),
        elevation: 0,
        actions: [
          if (ADD_GEN_CAT)
            IconButton(
              icon: Icon(Icons.add, color: AppColors.primaryGreen),
              tooltip: 'Add New Category',
              onPressed: () => _addNewCategory(),
            ),
          IconButton(
            icon: Icon(Icons.search, color: AppColors.primaryGreen),
            onPressed: () {
              // Focus on search field if it exists, or show search dialog
              if (_searchController.text.isNotEmpty) {
                _clearSearch();
              }
            },
          ),
          IconButton(
            icon: Icon(Icons.table_chart_outlined, color: AppColors.primaryGreen),
            tooltip: 'HSN & GST Rates',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const GeneralHsnGstRatesScreen(),
                ),
              );
            },
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: Icon(Icons.more_vert, color: AppColors.primaryGreen),
            onSelected: (value) {
              if (value == 'rate_tax') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RateTaxDefinitionScreen(),
                  ),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'rate_tax',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.percent_rounded),
                  title: Text('Rate based tax definition'),
                ),
              ),
            ],
          ),
          IconButton(
            icon: Icon(Icons.verified_user, color: AppColors.primaryGreen),
            tooltip: 'Check Duplicate Codes',
            onPressed: _checkDuplicateCodes,
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: AppColors.primaryGreen),
            onPressed: _loadGeneralCategories,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _categories.isEmpty
          ? Center(
              child: Text(
                'No categories found.',
                style: TextStyle(fontSize: 16, color: AppColors.primaryGrey),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search category or subcategory',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _isSearching
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: _clearSearch,
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    onChanged: _performSearch,
                  ),
                ),
                if (_isSearching)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Showing results for "${_searchController.text}"',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Expanded(
                  child: ListView.builder(
                    controller: _categoryListScrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filteredCategories.length,
                    itemBuilder: (context, index) {
                      return _buildCategoryCard(index);
                    },
                  ),
                ),

                // Add New Subcategory Button (after all categories)
              ],
            ),
    );
  }

  Widget _buildCategoryCard(int index) {
    final category = _filteredCategories[index];
    final groupHighlighted =
        _normCatCode(_highlightCategoryCode) == _normCatCode(category.code) &&
            (_highlightSubcategoryCode != null &&
                _highlightSubcategoryCode!.isNotEmpty);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          // Category Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: groupHighlighted
                  ? AppColors.primaryGreen.withOpacity(0.22)
                  : AppColors.primaryGreen.withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              border: groupHighlighted
                  ? Border.all(
                      color: AppColors.primaryGreen.withOpacity(0.65),
                      width: 1.5,
                    )
                  : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _toggleCategoryExpansion(index),
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      children: [
                        Icon(
                          category.isExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: AppColors.primaryGreen,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                category.categoryName,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${category.subcategories.length} subcategories',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.primaryGrey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (ADD_GEN_CAT)
                  IconButton(
                    icon: Icon(
                      Icons.add_circle_outline,
                      color: AppColors.primaryGreen,
                      size: 20,
                    ),
                    onPressed: () => _navigateToAddSubcategory(index),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Add Subcategory',
                  ),
                if (ADD_GEN_CAT)
                  IconButton(
                    icon: Icon(
                      Icons.data_object_outlined,
                      color: AppColors.primaryGreen,
                      size: 20,
                    ),
                    onPressed: () => _showImportSubcategoriesJsonDialog(index),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Import subcategories from JSON',
                  ),
              ],
            ),
          ),

          // Category Subcategories
          if (category.isExpanded) ...[
            const Divider(height: 1),
            Container(
              constraints: const BoxConstraints(maxHeight: 300),
              decoration: groupHighlighted
                  ? BoxDecoration(
                      color: AppColors.primaryGreen.withOpacity(0.07),
                    )
                  : null,
              child: ListView.builder(
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                itemCount: category.subcategories.length,
                itemBuilder: (context, subIndex) {
                  SubCategory subcategory = category.subcategories[subIndex];
                  final pinRow = groupHighlighted &&
                      _normSubCode(subcategory.code) ==
                          _normSubCode(_highlightSubcategoryCode);
                  return _HoverSubcategoryRow(
                    key: ValueKey(
                      '${_normCatCode(category.code)}::${_normSubCode(subcategory.code)}',
                    ),
                    pinnedHighlight: pinRow,
                    child: ListTile(
                      dense: true,
                      onTap: ADD_GEN_CAT
                          ? () =>
                              _navigateToEditSubcategory(index, subIndex)
                          : null,
                      title: Text(
                        subcategory.name,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        [
                          if (subcategory.code.trim().isNotEmpty)
                            'Code: ${subcategory.code.trim()}',
                          if ((subcategory.hsnCode ?? '').isNotEmpty)
                            'HSN: ${subcategory.hsnCode}',
                          'Unit: ${subcategory.unit ?? 'Piece'}',
                          if (subcategory.gstRate != null)
                            'GST: ${subcategory.gstRate}%',
                        ].join(' • '),
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.primaryGrey,
                        ),
                      ),
                      trailing: ADD_GEN_CAT
                          ? IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                                size: 18,
                              ),
                              onPressed: () =>
                                  _deleteSubcategory(index, subIndex),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Delete Subcategory',
                            )
                          : null,
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Full-width row hover highlight for web / desktop (mouse); no-op on touch.
/// [pinnedHighlight] is used after save to mark the row the user just edited.
class _HoverSubcategoryRow extends StatefulWidget {
  const _HoverSubcategoryRow({
    super.key,
    required this.child,
    this.pinnedHighlight = false,
  });

  final Widget child;
  final bool pinnedHighlight;

  @override
  State<_HoverSubcategoryRow> createState() => _HoverSubcategoryRowState();
}

class _HoverSubcategoryRowState extends State<_HoverSubcategoryRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final pin = widget.pinnedHighlight;
    final h = _hover;

    final Color bg;
    if (pin && h) {
      bg = AppColors.primaryGreen.withOpacity(0.42);
    } else if (pin) {
      bg = AppColors.primaryGreen.withOpacity(0.30);
    } else if (h) {
      bg = AppColors.primaryGreen.withOpacity(0.20);
    } else {
      bg = Colors.transparent;
    }

    final Border border;
    if (pin) {
      border = Border.all(
        color: AppColors.primaryGreen.withOpacity(0.95),
        width: 2.5,
      );
    } else if (h) {
      border = Border.all(
        color: AppColors.primaryGreen.withOpacity(0.55),
        width: 1.5,
      );
    } else {
      border = Border.all(color: Colors.transparent, width: 2.5);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        width: double.infinity,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: border,
          boxShadow: pin || h
              ? [
                  BoxShadow(
                    color: AppColors.primaryGreen.withOpacity(pin ? 0.35 : 0.2),
                    blurRadius: pin ? 12 : 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: widget.child,
      ),
    );
  }
}
