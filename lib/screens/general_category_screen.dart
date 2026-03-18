import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:xeebill_web/models/general_category_model.dart';
import 'package:xeebill_web/models/subcategory_model.dart';
import 'package:xeebill_web/screens/add_subcategory_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _loadGeneralCategories();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadGeneralCategories() async {
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

      // Sort subcategories alphabetically within each category
      for (var category in categories) {
        category.subcategories.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      }

      setState(() {
        _categories = categories;
        _filteredCategories = categories;
        _isLoading = false;
      });
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
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() {
        _filteredCategories = _categories;
        _isSearching = false;
      });
      return;
    }

    final List<GeneralCategory> results = [];

    for (final category in _categories) {
      final catName = category.categoryName.toLowerCase();
      final catCode = category.code.toLowerCase();

      final matchesCategory = catName.contains(q) || catCode.contains(q);

      final matchingSubs = category.subcategories.where((sub) {
        final name = sub.name.toLowerCase();
        final code = sub.code.toLowerCase();
        final hsn = (sub.hsnCode ?? '').toLowerCase();
        final desc = (sub.description ?? '').toLowerCase();
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

    setState(() {
      _filteredCategories = results;
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

  Future<void> _navigateToAddSubcategory(int index) async {
    final category = _filteredCategories[index];
    // Find the original category to get all subcategories
    final originalCategory = _categories.firstWhere(
      (c) => c.code == category.code,
      orElse: () => category,
    );
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
      // Reload categories to reflect changes
      _loadGeneralCategories();
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
      // Reload categories to reflect changes
      _loadGeneralCategories();
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
                          'subcategories': jsonEncode([]),
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
    final unitController = TextEditingController(text: 'Piece');
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

                // Create new subcategory
                SubCategory newSubcategory = SubCategory(
                  name: nameController.text,
                  code: codeController.text,
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

                // Add to category
                category.subcategories.add(newSubcategory);
                category.subcategories.sort(
                  (a, b) =>
                      a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                );

                // Update in Firestore
                await _updateCategoryInFirestore(category);

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

  Future<void> _updateCategoryInFirestore(GeneralCategory category) async {
    try {
      // Convert subcategories to JSON
      List<Map<String, dynamic>> subcategoriesJson = category.subcategories.map(
        (sub) {
          return {
            'code': sub.code,
            'name': sub.name,
            'attributes': sub.attributes,
            'attribute_types': sub.attributeTypes,
            'hsn_code': sub.hsnCode,
            'unit': sub.unit,
            'description': sub.description,
            'gst_rate': sub.gstRate,
          };
        },
      ).toList();

      await FirebaseFirestore.instance
          .collection('general_categories')
          .doc(category.id)
          .update({
            'subcategories': jsonEncode(subcategoriesJson),
            'updatedAt': DateTime.now(),
          });
    } catch (e) {
      debugPrint('Error updating category in Firestore: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating category: $e')));
      }
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
      // Find the original category to get all subcategories
      final originalCategory = _categories.firstWhere(
        (c) => c.code == category.code,
        orElse: () => category,
      );

      // Remove the subcategory from the original category
      originalCategory.subcategories.removeWhere(
        (sub) => sub.code == subcategory.code,
      );

      // Update in Firestore
      await _updateCategoryInFirestore(originalCategory);

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
              color: AppColors.primaryGreen.withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
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
              ],
            ),
          ),

          // Category Subcategories
          if (category.isExpanded) ...[
            const Divider(height: 1),
            Container(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                itemCount: category.subcategories.length,
                itemBuilder: (context, subIndex) {
                  SubCategory subcategory = category.subcategories[subIndex];
                  return ListTile(
                    dense: true,
                    title: Text(
                      subcategory.name,
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      [
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
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  Icons.edit_outlined,
                                  color: AppColors.primaryGreen,
                                  size: 18,
                                ),
                                onPressed: () =>
                                    _navigateToEditSubcategory(index, subIndex),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: 'Edit Subcategory',
                              ),
                              const SizedBox(width: 14),
                              IconButton(
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
                              ),
                            ],
                          )
                        : null,
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
