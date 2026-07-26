import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/category_model.dart';
import '../models/general_category_model.dart';
import '../models/subcategory_model.dart';

class ImportCategoriesScreen extends StatefulWidget {
  final String userId;

  const ImportCategoriesScreen({super.key, required this.userId});

  @override
  State<ImportCategoriesScreen> createState() => _ImportCategoriesScreenState();
}

class _ImportCategoriesScreenState extends State<ImportCategoriesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isSearching = false;

  List<GeneralCategory> _categories = [];
  List<GeneralCategory> _filteredCategories = [];

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

      final snapshot = await _firestore.collection('general_categories').get();

      final categories = snapshot.docs
          .map((doc) => GeneralCategory.fromFirestore(doc))
          .toList();

      // Sort by category name
      categories.sort(
        (a, b) => a.categoryName.toLowerCase().compareTo(
          b.categoryName.toLowerCase(),
        ),
      );

      await GeneralCategory.attachSubcategoriesFromCollection(categories);

      setState(() {
        _categories = categories;
        _filteredCategories = categories;
        _isLoading = false;
        _isSearching = false;
      });
    } catch (e) {
      debugPrint('Error loading general categories: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading categories: $e')));
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

      final original = _categories.firstWhere(
        (c) => c.code == cat.code,
        orElse: () => cat,
      );
      original.isExpanded = cat.isExpanded;
    });
  }

  void _toggleAllSubcategories(int index, bool? value) {
    final v = value ?? false;
    setState(() {
      final cat = _filteredCategories[index];
      cat.isAllSelected = v;
      for (final sub in cat.subcategories) {
        sub.isSelected = v;
      }

      final original = _categories.firstWhere(
        (c) => c.code == cat.code,
        orElse: () => cat,
      );
      original.isAllSelected = v;
      for (final sub in original.subcategories) {
        sub.isSelected = v;
      }
    });
  }

  void _toggleSubcategory(int catIndex, int subIndex) {
    setState(() {
      final cat = _filteredCategories[catIndex];
      final sub = cat.subcategories[subIndex];
      sub.isSelected = !sub.isSelected;

      final allSelected =
          cat.subcategories.isNotEmpty &&
          cat.subcategories.every((s) => s.isSelected);
      cat.isAllSelected = allSelected;

      final original = _categories.firstWhere(
        (c) => c.code == cat.code,
        orElse: () => cat,
      );
      final originalSub = original.subcategories.firstWhere(
        (s) => s.code == sub.code,
        orElse: () => sub,
      );
      originalSub.isSelected = sub.isSelected;
      original.isAllSelected =
          original.subcategories.isNotEmpty &&
          original.subcategories.every((s) => s.isSelected);
    });
  }

  Future<void> _importSelected() async {
    try {
      final List<SubCategory> selected = [];
      for (final cat in _categories) {
        selected.addAll(cat.subcategories.where((s) => s.isSelected));
      }

      if (selected.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No subcategories selected to import')),
        );
        return;
      }

      setState(() {
        _isLoading = true;
      });

      int imported = 0;
      int updated = 0;

      final batch = _firestore.batch();

      for (final sub in selected) {
        final code = sub.code.trim();
        if (code.isEmpty || !code.contains('-')) {
          debugPrint('Skipping invalid subcategory code: $code');
          continue;
        }

        final docRef = _firestore
            .collection('users')
            .doc(widget.userId)
            .collection('categories')
            .doc(code);

        final existingSnap = await docRef.get();

        String mergedAttributes = sub.attributes;
        String mergedAttributeTypes = sub.attributeTypes;
        bool isUpdate = false;

        if (existingSnap.exists) {
          final existing = CategoryModel.fromFirestore(existingSnap);
          mergedAttributes = _mergeAttributes(
            existing.attributes,
            sub.attributes,
          );
          mergedAttributeTypes = _mergeAttributeTypes(
            existing.attributeTypes,
            sub.attributeTypes,
          );
          isUpdate = true;
        }

        final category = CategoryModel(
          id: null,
          code: sub.code,
          parentCode: sub.code.split('-').first,
          name: sub.name,
          attributes: mergedAttributes,
          attributeTypes: mergedAttributeTypes,
          active: true,
          unit: sub.unit ?? 'Piece',
          hsnCode: sub.hsnCode ?? '',
          taxPercentage: sub.gstRate ?? 0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        batch.set(docRef, category.toMap(), SetOptions(merge: true));
        if (isUpdate) {
          updated++;
        } else {
          imported++;
        }
      }

      await batch.commit();

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Imported $imported new, updated $updated categories'),
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Error importing categories: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error importing: $e')));
    }
  }

  String _mergeAttributes(String existingJson, String newJson) {
    try {
      if (existingJson.isEmpty && newJson.isEmpty) return '';
      if (existingJson.isEmpty) return newJson;
      if (newJson.isEmpty) return existingJson;

      final existing = json.decode(existingJson) as Map<String, dynamic>;
      final incoming = json.decode(newJson) as Map<String, dynamic>;

      final merged = json.decode(json.encode(existing)) as Map<String, dynamic>;
      final incomingClone =
          json.decode(json.encode(incoming)) as Map<String, dynamic>;

      incomingClone.forEach((parentKey, newParentValue) {
        if (newParentValue is Map<String, dynamic>) {
          if (merged[parentKey] is Map<String, dynamic>) {
            final existingParent = Map<String, dynamic>.from(
              merged[parentKey] as Map,
            );
            newParentValue.forEach((childKey, newChildValue) {
              if (!existingParent.containsKey(childKey)) {
                existingParent[childKey] = newChildValue;
              }
            });
            merged[parentKey] = existingParent;
          } else {
            merged[parentKey] = newParentValue;
          }
        } else {
          if (!merged.containsKey(parentKey)) {
            merged[parentKey] = newParentValue;
          }
        }
      });

      return json.encode(merged);
    } catch (e) {
      debugPrint('Error merging attributes: $e');
      return newJson.isNotEmpty ? newJson : existingJson;
    }
  }

  String _mergeAttributeTypes(String existingJson, String newJson) {
    try {
      if (existingJson.isEmpty && newJson.isEmpty) return '';
      if (existingJson.isEmpty) return newJson;
      if (newJson.isEmpty) return existingJson;

      final existing = json.decode(existingJson) as Map<String, dynamic>;
      final incoming = json.decode(newJson) as Map<String, dynamic>;

      final merged = json.decode(json.encode(existing)) as Map<String, dynamic>;
      final incomingClone =
          json.decode(json.encode(incoming)) as Map<String, dynamic>;

      incomingClone.forEach((key, value) {
        if (!merged.containsKey(key)) {
          merged[key] = value;
        }
      });

      return json.encode(merged);
    } catch (e) {
      debugPrint('Error merging attribute types: $e');
      return existingJson.isNotEmpty ? existingJson : newJson;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Categories'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadGeneralCategories,
            tooltip: 'Reload',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _categories.isEmpty
          ? const Center(child: Text('No general categories found'))
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
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _importSelected,
                        icon: const Icon(Icons.download),
                        label: const Text('Import Selected'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildCategoryCard(int index) {
    final category = _filteredCategories[index];
    final selectedCount = category.subcategories
        .where((s) => s.isSelected)
        .length;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          InkWell(
            onTap: () => _toggleCategoryExpansion(index),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withOpacity(0.4),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    category.isExpanded ? Icons.expand_less : Icons.expand_more,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category.categoryName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${category.subcategories.length} subcategories'
                          '${selectedCount > 0 ? ' • $selectedCount selected' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selectedCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$selectedCount',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (category.isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Checkbox(
                    value: category.isAllSelected,
                    onChanged: (v) => _toggleAllSubcategories(index, v),
                  ),
                  const SizedBox(width: 4),
                  const Text('Select all', style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
            const Divider(height: 1),
            SizedBox(
              height: 220,
              child: ListView.builder(
                itemCount: category.subcategories.length,
                itemBuilder: (context, subIndex) {
                  final sub = category.subcategories[subIndex];
                  return CheckboxListTile(
                    dense: true,
                    title: Text(sub.name, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(
                      [
                        if ((sub.hsnCode ?? '').isNotEmpty)
                          'HSN: ${sub.hsnCode}',
                        'Unit: ${sub.unit ?? 'Piece'}',
                        if (sub.gstRate != null) 'GST: ${sub.gstRate}%',
                      ].join(' • '),
                      style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                    ),
                    value: sub.isSelected,
                    onChanged: (_) => _toggleSubcategory(index, subIndex),
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
