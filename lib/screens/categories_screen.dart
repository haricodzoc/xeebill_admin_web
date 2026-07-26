import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/category_model.dart';
import '../models/item_model.dart';
import '../utils/constants.dart';
import 'deleted_category_items_screen.dart';
import 'hsn_gst_rates_screen.dart';
import 'import_categories_screen.dart';

class CategoriesScreen extends StatefulWidget {
  final String userId;

  const CategoriesScreen({super.key, required this.userId});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = true;
  String? _errorMessage;
  List<CategoryModel> _categories = [];
  Map<String, bool> _expansionStates = {};
  List<Map<String, dynamic>> _groupedCategories = [];
  final Set<String> _expandedGroupCodes = <String>{};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  String _normalizeForSearch(String input) {
    final lower = input.trim().toLowerCase();
    // Remove all whitespace (including NBSP) and punctuation so "ledmodule"
    // matches "LED Module" / "LED-Module" / "LED Module".
    final noSpace = lower.replaceAll(RegExp(r'[\\s\\u00A0]+'), '');
    return noSpace.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// In‑memory editable attributes per category code
  /// Structure: { categoryCode: { attributeName: attributeValueMapOrConfig } }
  final Map<String, Map<String, dynamic>> _categoryAttributes = {};

  /// Attribute types per category code
  /// Structure: { categoryCode: { attributeName: typeInt } }
  final Map<String, Map<String, int>> _categoryAttributeTypes = {};

  /// `categoryCode::attributeName` after a successful copy.
  String? _attributeValuesCopiedFrom;

  @override
  void initState() {
    super.initState();
    _fetchCategories();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchCategories() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      debugPrint('Fetching categories for user: ${widget.userId}');

      // First, find the user document
      String? userDocumentId;

      // Try to find user by userId field
      final userQuery = await _firestore
          .collection('users')
          .where('userId', isEqualTo: widget.userId)
          .limit(1)
          .get();

      if (userQuery.docs.isNotEmpty) {
        userDocumentId = userQuery.docs.first.id;
        debugPrint('Found user document: $userDocumentId');
      } else {
        // Try by document ID
        final userDoc = await _firestore
            .collection('users')
            .doc(widget.userId)
            .get();

        if (userDoc.exists) {
          userDocumentId = widget.userId;
          debugPrint('Found user by document ID: $userDocumentId');
        }
      }

      if (userDocumentId == null) {
        setState(() {
          _errorMessage = 'User document not found';
          _isLoading = false;
        });
        return;
      }

      // Fetch categories directly from users/{userId}/categories subcollection
      debugPrint('Fetching categories from users/$userDocumentId/categories');

      final categoriesSnapshot = await _firestore
          .collection('users')
          .doc(userDocumentId)
          .collection('categories')
          .get();

      debugPrint('Found ${categoriesSnapshot.docs.length} categories');

      final List<CategoryModel> allCategories = [];

      for (var categoryDoc in categoriesSnapshot.docs) {
        try {
          final category = CategoryModel.fromFirestore(categoryDoc);
          allCategories.add(category);
        } catch (e) {
          debugPrint('Error parsing category ${categoryDoc.id}: $e');
        }
      }

      // Sort categories by name
      allCategories.sort((a, b) => a.name.compareTo(b.name));

      // Build editable attribute structures for each category
      final Map<String, Map<String, dynamic>> attributesByCategory = {};
      final Map<String, Map<String, int>> typesByCategory = {};

      for (final category in allCategories) {
        final attrs =
            _parseAttributes(category.attributes) ?? <String, dynamic>{};
        final types =
            _parseAttributeTypes(category.attributeTypes) ?? <String, int>{};

        // Deep copy so we can safely mutate in UI
        attributesByCategory[category.code] = {
          for (final entry in attrs.entries)
            entry.key: entry.value is Map<String, dynamic>
                ? Map<String, dynamic>.from(entry.value as Map<String, dynamic>)
                : entry.value,
        };
        typesByCategory[category.code] = Map<String, int>.from(types);
      }

      // Load general categories to group by prefix code
      final generalSnapshot = await _firestore
          .collection('general_categories')
          .get();
      final List<Map<String, String>> generalDefs = generalSnapshot.docs
          .map((doc) {
            final data = doc.data();
            return {
              'code': (data['code'] ?? '').toString(),
              'name': (data['category_name'] ?? 'Unknown Category').toString(),
            };
          })
          .where((g) => g['code']!.isNotEmpty)
          .toList();

      // Track which categories have been grouped
      final Set<String> groupedCategoryCodes = <String>{};
      final List<Map<String, dynamic>> grouped = [];

      for (final def in generalDefs) {
        final generalCode = def['code']!;
        final generalName = def['name']!;

        final matching = allCategories.where((cat) {
          final parts = cat.code.split('-');
          final prefix = parts.isNotEmpty ? parts[0] : '';
          return prefix == generalCode && cat.active == true;
        }).toList();

        if (matching.isEmpty) continue;

        // Sort subcategories alphabetically by name
        matching.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );

        // Track which categories we've grouped
        for (final cat in matching) {
          groupedCategoryCodes.add(cat.code);
        }

        grouped.add({
          'category_name': generalName,
          'category_code': generalCode,
          'subcategories': matching,
        });
      }

      // Find subcategories that don't match any general category
      // These should still be displayed, grouped by their prefix
      final ungroupedCategories = allCategories.where((cat) {
        return cat.active == true && !groupedCategoryCodes.contains(cat.code);
      }).toList();

      if (ungroupedCategories.isNotEmpty) {
        // Group ungrouped categories by their prefix code
        final Map<String, List<CategoryModel>> ungroupedByPrefix = {};
        for (final cat in ungroupedCategories) {
          final parts = cat.code.split('-');
          final prefix = parts.isNotEmpty ? parts[0] : cat.code;
          ungroupedByPrefix.putIfAbsent(prefix, () => []).add(cat);
        }

        // Add ungrouped categories as separate groups
        for (final entry in ungroupedByPrefix.entries) {
          final prefix = entry.key;
          final categories = entry.value;
          categories.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
          grouped.add({
            'category_name': 'Other ($prefix)',
            'category_code': prefix,
            'subcategories': categories,
          });
        }
      }

      // Sort groups by category_name
      grouped.sort(
        (a, b) => (a['category_name'] as String).toLowerCase().compareTo(
          (b['category_name'] as String).toLowerCase(),
        ),
      );

      setState(() {
        _categories = allCategories;
        _groupedCategories = grouped;
        _categoryAttributes
          ..clear()
          ..addAll(attributesByCategory);
        _categoryAttributeTypes
          ..clear()
          ..addAll(typesByCategory);
        _isLoading = false;
      });

      debugPrint(
        'Successfully loaded ${allCategories.length} categories, grouped into ${grouped.length} general categories',
      );
    } catch (e) {
      debugPrint('Error fetching categories: $e');
      setState(() {
        _errorMessage = 'Error fetching categories: $e';
        _isLoading = false;
      });
    }
  }

  Map<String, dynamic>? _parseAttributes(String attributesJson) {
    if (attributesJson.isEmpty) return null;
    try {
      return jsonDecode(attributesJson) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Error parsing attributes JSON: $e');
      return null;
    }
  }

  Map<String, int>? _parseAttributeTypes(String attributeTypesJson) {
    if (attributeTypesJson.isEmpty) return null;
    try {
      final Map<String, dynamic> typesMap = jsonDecode(attributeTypesJson);
      return typesMap.map((key, value) {
        final intType = value is int
            ? value
            : int.tryParse(value.toString()) ?? 1;
        return MapEntry(key, intType);
      });
    } catch (e) {
      debugPrint('Error parsing attributeTypes JSON: $e');
      return null;
    }
  }

  List<CategoryModel> _getChildCategories(String parentCode) {
    return _categories
        .where((cat) => cat.parentCode == parentCode && cat.active == true)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  List<Map<String, dynamic>> get _filteredGroupedCategories {
    final query = _normalizeForSearch(_searchQuery);
    if (query.isEmpty) return _groupedCategories;

    return _groupedCategories.where((group) {
      final groupName = _normalizeForSearch(group['category_name'] as String? ?? '');
      final groupCode = _normalizeForSearch(group['category_code'] as String? ?? '');
      final subcategories =
          group['subcategories'] as List<CategoryModel>? ?? [];

      // Check if group name or code matches
      if (groupName.contains(query) || groupCode.contains(query)) {
        return true;
      }

      // Check if any subcategory matches
      final matchingSubcategories = subcategories.where((subcat) {
        final subcatName = _normalizeForSearch(subcat.name);
        final subcatCode = _normalizeForSearch(subcat.code);
        final subcatHsn = _normalizeForSearch(subcat.hsnCode);
        return subcatName.contains(query) ||
            subcatCode.contains(query) ||
            subcatHsn.contains(query);
      }).toList();

      if (matchingSubcategories.isNotEmpty) {
        // Update the group to only include matching subcategories
        group['subcategories'] = matchingSubcategories;
        return true;
      }

      return false;
    }).toList();
  }

  Future<void> _saveCategoryAttributes(CategoryModel category) async {
    final attrs = _categoryAttributes[category.code] ?? <String, dynamic>{};
    final types = _categoryAttributeTypes[category.code] ?? <String, int>{};

    final updated = CategoryModel(
      id: category.id,
      code: category.code,
      parentCode: category.parentCode,
      name: category.name,
      attributes: jsonEncode(attrs),
      attributeTypes: jsonEncode(types),
      active: category.active,
      unit: category.unit,
      hsnCode: category.hsnCode,
      taxPercentage: category.taxPercentage,
      createdAt: category.createdAt,
      updatedAt: DateTime.now(),
    );

    try {
      // Update Firestore document in users/{userId}/categories/{code}
      await _firestore
          .collection('users')
          .doc(widget.userId)
          .collection('categories')
          .doc(category.code)
          .set(updated.toMap(), SetOptions(merge: true));

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Category attributes saved')),
      );
    } catch (e) {
      debugPrint('Error saving category attributes: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error saving attributes: $e')));
    }
  }

  Future<String?> _getUserDocumentId() async {
    try {
      // Try to find user by userId field
      final userQuery = await _firestore
          .collection('users')
          .where('userId', isEqualTo: widget.userId)
          .limit(1)
          .get();

      if (userQuery.docs.isNotEmpty) {
        return userQuery.docs.first.id;
      }

      // Try by document ID
      final userDoc = await _firestore
          .collection('users')
          .doc(widget.userId)
          .get();

      if (userDoc.exists) {
        return widget.userId;
      }

      return null;
    } catch (e) {
      debugPrint('Error getting user document ID: $e');
      return null;
    }
  }

  Future<int> _checkItemsUsingCategory(String categoryCode) async {
    try {
      final userDocumentId = await _getUserDocumentId();

      if (userDocumentId == null) {
        return 0;
      }

      // Count items using this category
      final itemsSnapshot = await _firestore
          .collection('users')
          .doc(userDocumentId)
          .collection('items')
          .where('category_code', isEqualTo: categoryCode)
          .get();

      return itemsSnapshot.docs.length;
    } catch (e) {
      debugPrint('Error checking items using category: $e');
      return 0;
    }
  }

  Future<void> _handleDeleteCategory(CategoryModel category) async {
    // Check if items are using this category
    final itemCount = await _checkItemsUsingCategory(category.code);

    if (itemCount > 0) {
      // Show dialog with hard delete option
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cannot Delete Category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This category is being used by $itemCount item${itemCount == 1 ? '' : 's'}.',
              ),
              const SizedBox(height: 8),
              const Text(
                'You can perform a hard delete to remove the category anyway. '
                'After deletion, you will see all items that were using this category.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Hard Delete'),
            ),
          ],
        ),
      );

      if (result == true) {
        await _hardDeleteCategory(category, itemCount);
      }
    } else {
      // No items using it, can delete normally
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Category'),
          content: Text('Are you sure you want to delete "${category.name}"?'),
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

      if (confirm == true) {
        await _deleteCategory(category);
      }
    }
  }

  Future<void> _deleteCategory(CategoryModel category) async {
    try {
      final userDocumentId = await _getUserDocumentId();

      if (userDocumentId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User document not found')),
          );
        }
        return;
      }

      // Delete the category
      await _firestore
          .collection('users')
          .doc(userDocumentId)
          .collection('categories')
          .doc(category.code)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Category deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _fetchCategories();
      }
    } catch (e) {
      debugPrint('Error deleting category: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error deleting category: $e')));
      }
    }
  }

  Future<void> _hardDeleteCategory(
    CategoryModel category,
    int itemCount,
  ) async {
    try {
      final userDocumentId = await _getUserDocumentId();

      if (userDocumentId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User document not found')),
          );
        }
        return;
      }

      // Delete the category
      await _firestore
          .collection('users')
          .doc(userDocumentId)
          .collection('categories')
          .doc(category.code)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Category deleted. $itemCount item${itemCount == 1 ? '' : 's'} still using this category.',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );

        // Navigate to screen showing items using deleted category
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DeletedCategoryItemsScreen(
              userId: widget.userId,
              categoryCode: category.code,
              categoryName: category.name,
            ),
          ),
        );

        _fetchCategories();
      }
    } catch (e) {
      debugPrint('Error hard deleting category: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error deleting category: $e')));
      }
    }
  }

  Future<void> _showEditCategoryDialog(CategoryModel category) async {
    final nameController = TextEditingController(text: category.name);
    final taxController = TextEditingController(
      text: category.taxPercentage.toStringAsFixed(2),
    );
    final formKey = GlobalKey<FormState>();
    final unitNames = UNITS
        .map((u) => (u['name'] as String?)?.trim() ?? '')
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    String selectedUnit = category.unit.trim();
    if (selectedUnit.isEmpty) {
      selectedUnit = unitNames.isNotEmpty ? unitNames.first : 'Piece';
    }
    if (!unitNames.contains(selectedUnit)) {
      unitNames.add(selectedUnit);
      unitNames.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Category'),
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
                    ),
                    validator: (value) => value?.isEmpty ?? true
                        ? 'Category name is required'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedUnit,
                    items: unitNames
                        .map(
                          (unit) => DropdownMenuItem<String>(
                            value: unit,
                            child: Text(unit),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        selectedUnit = value;
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: 'Unit *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        value?.isEmpty ?? true ? 'Unit is required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: taxController,
                    decoration: const InputDecoration(
                      labelText: 'Tax Percentage *',
                      border: OutlineInputBorder(),
                      hintText: 'e.g., 18.00',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) {
                      if (value?.isEmpty ?? true) {
                        return 'Tax percentage is required';
                      }
                      final tax = double.tryParse(value!);
                      if (tax == null || tax < 0) {
                        return 'Please enter a valid tax percentage';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Note: Changing tax will update all items using this category.',
                    style: TextStyle(fontSize: 12, color: Colors.orange[700]),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final newName = nameController.text.trim();
                  final newUnit = selectedUnit.trim();
                  final newTax =
                      double.tryParse(taxController.text.trim()) ?? 0.0;
                  final oldTax = category.taxPercentage;

                  await _updateCategory(
                    category,
                    newName,
                    newUnit,
                    newTax,
                    oldTax != newTax,
                  );
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateCategory(
    CategoryModel category,
    String newName,
    String newUnit,
    double newTax,
    bool taxChanged,
  ) async {
    try {
      final userDocumentId = await _getUserDocumentId();

      if (userDocumentId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User document not found')),
          );
        }
        return;
      }

      // Update category
      final updatedCategory = CategoryModel(
        id: category.id,
        code: category.code,
        parentCode: category.parentCode,
        name: newName,
        attributes: category.attributes,
        attributeTypes: category.attributeTypes,
        active: category.active,
        unit: newUnit,
        hsnCode: category.hsnCode,
        taxPercentage: newTax,
        createdAt: category.createdAt,
        updatedAt: DateTime.now(),
      );

      await _firestore
          .collection('users')
          .doc(userDocumentId)
          .collection('categories')
          .doc(category.code)
          .set(updatedCategory.toMap(), SetOptions(merge: true));

      // If tax changed, update all items using this category
      if (taxChanged) {
        await _updateItemsTaxForCategory(category.code, newTax, userDocumentId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              taxChanged
                  ? 'Category updated. Tax updated in all items using this category.'
                  : 'Category updated successfully',
            ),
            backgroundColor: Colors.green,
          ),
        );
        _fetchCategories();
      }
    } catch (e) {
      debugPrint('Error updating category: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating category: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateItemsTaxForCategory(
    String categoryCode,
    double newTax,
    String userDocumentId,
  ) async {
    try {
      // Fetch all items with this category code
      final itemsSnapshot = await _firestore
          .collection('users')
          .doc(userDocumentId)
          .collection('items')
          .where('category_code', isEqualTo: categoryCode)
          .get();

      debugPrint(
        'Updating tax for ${itemsSnapshot.docs.length} items in category $categoryCode',
      );

      // Update each item's tax percentage using the same pattern as edit_item_dialog
      final batch = _firestore.batch();
      int updateCount = 0;

      for (var itemDoc in itemsSnapshot.docs) {
        try {
          // Get the current item data
          final currentItem = ItemModel.fromFirestore(itemDoc);

          // Create updated item with new tax
          final updatedItem = ItemModel(
            id: currentItem.id,
            code: currentItem.code,
            name: currentItem.name,
            categoryCode: currentItem.categoryCode,
            price: currentItem.price,
            quantity: currentItem.quantity,
            availableQty: currentItem.availableQty,
            sellPrice: currentItem.sellPrice,
            hsnCode: currentItem.hsnCode,
            taxPerc: newTax, // Updated tax
            description: currentItem.description,
            attributes: currentItem.attributes,
            printed: currentItem.printed,
            mapped: currentItem.mapped,
            active: currentItem.active,
            unit: currentItem.unit,
            scannedBarcode: currentItem.scannedBarcode,
            listedOnline: currentItem.listedOnline,
            additionalInfo: currentItem.additionalInfo,
            locationId: currentItem.locationId,
            subProfileId: currentItem.subProfileId,
            createdAt: currentItem.createdAt,
            updatedAt: DateTime.now(), // Set current time when updating
          );

          // Use set with merge, same pattern as edit_item_dialog
          batch.set(
            itemDoc.reference,
            updatedItem.toMap(),
            SetOptions(merge: true),
          );
          updateCount++;
        } catch (e) {
          debugPrint('Error processing item ${itemDoc.id}: $e');
          // Continue with other items
        }
      }

      // Commit batch update
      if (updateCount > 0) {
        await batch.commit();
        debugPrint('Successfully updated tax for $updateCount items');
      }
    } catch (e) {
      debugPrint('Error updating items tax: $e');
      // Don't throw error, just log it - category update already succeeded
    }
  }

  void _showAddAttributeDialog(String categoryCode) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Attribute'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Attribute name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                setState(() {
                  _categoryAttributes.putIfAbsent(
                    categoryCode,
                    () => <String, dynamic>{},
                  );
                  _categoryAttributes[categoryCode]![name] =
                      <String, dynamic>{};
                });
              }
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showDeleteAttributeDialog(String categoryCode, String attributeName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Attribute'),
        content: Text(
          'Are you sure you want to delete \"$attributeName\" and all its values?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _categoryAttributes[categoryCode]?.remove(attributeName);
                _categoryAttributeTypes[categoryCode]?.remove(attributeName);
              });
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showAddAttributeValueDialog(String categoryCode, String attributeName) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add value to $attributeName'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Value',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                setState(() {
                  final catAttrs =
                      _categoryAttributes[categoryCode] ?? <String, dynamic>{};
                  final raw = catAttrs[attributeName];
                  if (raw is Map<String, dynamic>) {
                    raw[value] = true;
                  } else {
                    catAttrs[attributeName] = <String, dynamic>{value: true};
                  }
                  _categoryAttributes[categoryCode] = catAttrs;
                });
              }
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditOrDeleteAttributeValueDialog(
    String categoryCode,
    String attributeName,
    String valueKey,
  ) {
    final controller = TextEditingController(text: valueKey);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit value'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Value',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                final catAttrs = _categoryAttributes[categoryCode];
                if (catAttrs != null &&
                    catAttrs[attributeName] is Map<String, dynamic>) {
                  final map = catAttrs[attributeName] as Map<String, dynamic>;
                  map.remove(valueKey);
                }
              });
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
          TextButton(
            onPressed: () {
              final newKey = controller.text.trim();
              if (newKey.isNotEmpty && newKey != valueKey) {
                setState(() {
                  final catAttrs = _categoryAttributes[categoryCode];
                  if (catAttrs != null &&
                      catAttrs[attributeName] is Map<String, dynamic>) {
                    final map = catAttrs[attributeName] as Map<String, dynamic>;
                    final existing = map[valueKey];
                    map.remove(valueKey);
                    // Do not overwrite if key already exists
                    map.putIfAbsent(newKey, () => existing ?? true);
                  }
                });
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String _attributeCopyKey(String categoryCode, String attributeName) {
    return '$categoryCode::$attributeName';
  }

  Map<String, dynamic>? _selectAttributeValues(
    String categoryCode,
    String attributeName,
  ) {
    final catAttrs = _categoryAttributes[categoryCode];
    if (catAttrs == null) return null;
    final raw = catAttrs[attributeName];
    if (raw is! Map<String, dynamic>) return null;

    final values = <String, dynamic>{};
    for (final entry in raw.entries) {
      final k = entry.key.toString();
      if (k == 'default_text' ||
          k == 'default_date' ||
          k == 'start_date' ||
          k == 'end_date') {
        continue;
      }
      final v = entry.value;
      if (v is bool || v is int || v is num) {
        values[k] = v == true || v == 1;
      }
    }
    return values;
  }

  void _copyAttributeValues(String categoryCode, String attributeName) {
    final values = _selectAttributeValues(categoryCode, attributeName);
    if (values == null || values.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No attribute values to copy'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    COPIED_ATTRIBUTE_VALUE = jsonEncode(values);
    setState(() {
      _attributeValuesCopiedFrom =
          _attributeCopyKey(categoryCode, attributeName);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Copied ${values.length} value(s) from "$attributeName"',
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _pasteAttributeValues(String categoryCode, String attributeName) {
    if (COPIED_ATTRIBUTE_VALUE.isEmpty) return;

    try {
      final copied = jsonDecode(COPIED_ATTRIBUTE_VALUE) as Map<String, dynamic>;
      var addedCount = 0;

      setState(() {
        final catAttrs = _categoryAttributes.putIfAbsent(
          categoryCode,
          () => <String, dynamic>{},
        );
        if (catAttrs[attributeName] is! Map<String, dynamic>) {
          catAttrs[attributeName] = <String, dynamic>{};
        }
        final map = catAttrs[attributeName] as Map<String, dynamic>;

        for (final entry in copied.entries) {
          final key = entry.key.toString();
          if (!map.containsKey(key)) {
            map[key] = entry.value == true || entry.value == 1;
            addedCount++;
          }
        }

        COPIED_ATTRIBUTE_VALUE = '';
        _attributeValuesCopiedFrom = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            addedCount > 0
                ? 'Pasted $addedCount value(s) to "$attributeName"'
                : 'All values already exist in "$attributeName"',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      COPIED_ATTRIBUTE_VALUE = '';
      setState(() => _attributeValuesCopiedFrom = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to paste attribute values: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildCopyPasteAttributeValuesLink(
    String categoryCode,
    String attributeName,
  ) {
    final copyKey = _attributeCopyKey(categoryCode, attributeName);

    if (_attributeValuesCopiedFrom == copyKey) {
      return Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, top: 8),
        child: Center(
          child: Text(
            'Attribute values copied',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ),
      );
    }

    if (COPIED_ATTRIBUTE_VALUE.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, top: 8),
        child: InkWell(
          onTap: () => _pasteAttributeValues(categoryCode, attributeName),
          child: Center(
            child: Text(
              'Paste attribute values',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.green[700],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 12),
      child: InkWell(
        onTap: () => _copyAttributeValues(categoryCode, attributeName),
        child: Center(
          child: Text(
            'Copy attribute values',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.green[700],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttributeChildren(
    String categoryCode,
    String attributeName,
    Map<String, dynamic> attributeValue,
    int? attributeType,
  ) {
    if (attributeValue.isEmpty) {
      // Empty attribute - show based on type
      if (attributeType == 3) {
        // Text field
        final defaultText = attributeValue['default_text']?.toString() ?? '';
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            defaultText.isEmpty ? 'No default value' : 'Default: $defaultText',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
        );
      } else if (attributeType == 4) {
        // Date field
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Date field (no default dates)',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
        );
      } else {
        // Empty select field - show helper text + Add value button
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No values',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () =>
                    _showAddAttributeValueDialog(categoryCode, attributeName),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add value', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        );
      }
    }

    // Check if this is a text or date field
    if (attributeValue.containsKey('default_text')) {
      // Text field
      final defaultText = attributeValue['default_text']?.toString() ?? '';
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          'Default: $defaultText',
          style: const TextStyle(fontSize: 13),
        ),
      );
    } else if (attributeValue.containsKey('default_date') ||
        attributeValue.containsKey('start_date') ||
        attributeValue.containsKey('end_date')) {
      // Date field
      final defaultDate = attributeValue['default_date']?.toString();
      final startDate = attributeValue['start_date']?.toString();
      final endDate = attributeValue['end_date']?.toString();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (defaultDate != null)
              Text(
                'Default Date: $defaultDate',
                style: const TextStyle(fontSize: 13),
              ),
            if (startDate != null)
              Text(
                'Start Date: $startDate',
                style: const TextStyle(fontSize: 13),
              ),
            if (endDate != null)
              Text('End Date: $endDate', style: const TextStyle(fontSize: 13)),
          ],
        ),
      );
    } else {
      // Select field with values - editable checkbox list
      final sortedEntries = attributeValue.entries.toList()
        ..sort((a, b) {
          // Natural sort
          final aStr = a.key.toString();
          final bStr = b.key.toString();
          return aStr.compareTo(bStr);
        });

      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Column(
          children: [
            ...sortedEntries.map((entry) {
              final isSelected = entry.value == true || entry.value == 1;
              return GestureDetector(
                onLongPress: () {
                  _showEditOrDeleteAttributeValueDialog(
                    categoryCode,
                    attributeName,
                    entry.key.toString(),
                  );
                },
                child: CheckboxListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 0,
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Transform.translate(
                    offset: const Offset(-14, 0),
                    child: Text(
                      entry.key.toString(),
                      maxLines: 2,
                      overflow: TextOverflow.visible,
                      style: TextStyle(
                        fontSize: 13,
                        color: isSelected
                            ? Colors.green[700]
                            : Colors.grey[600],
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  value: isSelected,
                  activeColor: Colors.green[700],
                  onChanged: (val) {
                    setState(() {
                      final catAttrs = _categoryAttributes[categoryCode];
                      if (catAttrs != null &&
                          catAttrs[attributeName] is Map<String, dynamic>) {
                        final map =
                            catAttrs[attributeName] as Map<String, dynamic>;
                        map[entry.key] = val == true;
                      }
                    });
                  },
                ),
              );
            }).toList(),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    _showAddAttributeValueDialog(categoryCode, attributeName),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add value', style: TextStyle(fontSize: 12)),
              ),
            ),
            _buildCopyPasteAttributeValuesLink(categoryCode, attributeName),
          ],
        ),
      );
    }
  }

  Widget _buildAttributesSection(CategoryModel category) {
    final attributesMap =
        _categoryAttributes[category.code] ?? <String, dynamic>{};
    final attributeTypesMap =
        _categoryAttributeTypes[category.code] ?? <String, int>{};

    if (attributesMap.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          'No attributes',
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
      );
    }

    final sortedAttributes = attributesMap.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _showAddAttributeDialog(category.code),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add attribute', style: TextStyle(fontSize: 12)),
          ),
        ),
        ...sortedAttributes.map((entry) {
          final attributeName = entry.key;
          final attributeValue = entry.value;
          final attributeType = attributeTypesMap[attributeName];

          final expansionKey = '${category.code}_$attributeName';
          final isExpanded = _expansionStates[expansionKey] ?? false;

          return GestureDetector(
            onLongPress: () =>
                _showDeleteAttributeDialog(category.code, attributeName),
            child: Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: isExpanded,
                onExpansionChanged: (expanded) {
                  setState(() {
                    _expansionStates[expansionKey] = expanded;
                  });
                },
                leading: Icon(
                  attributeType == 3
                      ? Icons.text_fields
                      : attributeType == 4
                      ? Icons.calendar_today
                      : Icons.folder,
                  size: 18,
                  color: Colors.green[700],
                ),
                title: Text(
                  attributeName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                childrenPadding: const EdgeInsets.only(
                  left: 0,
                  right: 0,
                  bottom: 8,
                ),
                children: [
                  _buildAttributeChildren(
                    category.code,
                    attributeName,
                    attributeValue is Map<String, dynamic>
                        ? attributeValue
                        : <String, dynamic>{},
                    attributeType,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildCategoryCard(CategoryModel category) {
    final childCategories = _getChildCategories(category.code);
    final categoryKey = category.code;
    final isExpanded = _expansionStates[categoryKey] ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.green[100],
                  child: Icon(Icons.category, color: Colors.green[700]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Code: ${category.code}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                      if (category.parentCode.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Parent: ${category.parentCode}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        'Unit: ${category.unit} | HSN: ${category.hsnCode} | Tax: ${category.taxPercentage.toStringAsFixed(2)}%',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Chip(
                  label: Text(category.active ? 'Active' : 'Inactive'),
                  backgroundColor: category.active
                      ? Colors.green[50]
                      : Colors.red[50],
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: category.active
                        ? Colors.green[700]
                        : Colors.red[700],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  onPressed: () => _showEditCategoryDialog(category),
                  tooltip: 'Edit category',
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _handleDeleteCategory(category),
                  tooltip: 'Delete category',
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Attributes section
            Container(
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Theme(
                data: Theme.of(context).copyWith(
                  dividerColor: Colors.transparent,
                  expansionTileTheme: ExpansionTileThemeData(
                    iconColor: Colors.green[700],
                    collapsedIconColor: Colors.green[700],
                  ),
                ),
                child: ExpansionTile(
                  initiallyExpanded: isExpanded,
                  onExpansionChanged: (expanded) {
                    setState(() {
                      _expansionStates[categoryKey] = expanded;
                    });
                  },
                  tilePadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 0,
                  ),
                  childrenPadding: EdgeInsets.zero,
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Attributes',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextButton(
                        onPressed: () => _saveCategoryAttributes(category),
                        child: const Text(
                          'Save',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  children: [_buildAttributesSection(category)],
                ),
              ),
            ),
            // Child categories section
            if (childCategories.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    dividerColor: Colors.transparent,
                    expansionTileTheme: ExpansionTileThemeData(
                      iconColor: Colors.blue[700],
                      collapsedIconColor: Colors.blue[700],
                    ),
                  ),
                  child: ExpansionTile(
                    initiallyExpanded:
                        _expansionStates['${categoryKey}_children'] ?? false,
                    onExpansionChanged: (expanded) {
                      setState(() {
                        _expansionStates['${categoryKey}_children'] = expanded;
                      });
                    },
                    tilePadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 0,
                    ),
                    childrenPadding: const EdgeInsets.all(8),
                    title: Text(
                      'Child Categories (${childCategories.length})',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.blue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    children: childCategories.map((child) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.subdirectory_arrow_right,
                              size: 16,
                              color: Colors.blue[700],
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                child.name,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            Text(
                              child.code,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Categories'),
            if (!_isLoading && _groupedCategories.isNotEmpty)
              Text(
                '${_groupedCategories.length} categor${_groupedCategories.length == 1 ? 'y' : 'ies'}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.table_chart_outlined),
            tooltip: 'HSN & GST Rates',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      HsnGstRatesScreen(userId: widget.userId),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _fetchCategories,
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Import categories',
            onPressed: () async {
              final imported = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      ImportCategoriesScreen(userId: widget.userId),
                ),
              );
              if (imported == true) {
                _fetchCategories();
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.red[700]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _fetchCategories,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : _groupedCategories.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.category_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No categories found',
                    style: TextStyle(color: Colors.grey[600], fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'User ID: ${widget.userId}',
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _fetchCategories,
              child: Column(
                children: [
                  // Search bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText:
                            'Search by category or subcategory name, code, or HSN',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setState(() {
                                    _searchQuery = '';
                                    _searchController.clear();
                                  });
                                },
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
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                    ),
                  ),
                  if (_searchQuery.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Showing results for "${_searchQuery}"',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  // Categories List
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16.0),
                      itemCount: _filteredGroupedCategories.length,
                      itemBuilder: (context, groupIndex) {
                        final group = _filteredGroupedCategories[groupIndex];
                        final String groupName =
                            (group['category_name'] as String?) ?? '';
                        final String groupCode =
                            (group['category_code'] as String?) ?? '';
                        final List<CategoryModel> subcategories =
                            (group['subcategories'] as List<CategoryModel>);

                        return Card(
                          key: ValueKey(
                            groupCode.isNotEmpty
                                ? groupCode
                                : 'group_$groupIndex',
                          ),
                          margin: const EdgeInsets.only(bottom: 16),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Theme(
                            data: Theme.of(
                              context,
                            ).copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              key: ValueKey('exp_$groupCode'),
                              initiallyExpanded: _expandedGroupCodes.contains(
                                groupCode,
                              ),
                              onExpansionChanged: (expanded) {
                                setState(() {
                                  if (expanded) {
                                    _expandedGroupCodes.add(groupCode);
                                  } else {
                                    _expandedGroupCodes.remove(groupCode);
                                  }
                                });
                              },
                              tilePadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              childrenPadding: const EdgeInsets.only(
                                left: 8,
                                right: 8,
                                bottom: 16,
                              ),
                              leading: const Icon(Icons.category),
                              title: Text(
                                groupName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '${subcategories.length} subcategories',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ),
                              children: subcategories
                                  .map((cat) => _buildCategoryCard(cat))
                                  .toList(),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
