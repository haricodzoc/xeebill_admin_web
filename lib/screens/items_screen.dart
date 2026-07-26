import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import '../models/item_model.dart';
import '../models/category_model.dart';
import '../utils/item_list_filters.dart';
import 'edit_item_dialog.dart';
import 'package:intl/intl.dart';

class _LocationOption {
  final String id;
  final String name;
  const _LocationOption({required this.id, required this.name});
}

class ItemsScreen extends StatefulWidget {
  final String userId;

  const ItemsScreen({super.key, required this.userId});

  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends State<ItemsScreen> {
  /// Location filter value for items tied to sub-profiles not mapped to any business location.
  static const String _defaultLocationFilterValue = '__default_unmapped_profiles__';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  String? _errorMessage;
  List<ItemModel> _items = [];
  String _searchQuery = '';
  String? _userDocumentId;
  Map<String, List<Map<String, dynamic>>> _itemMappingsByCode = {};
  String?
  _checkingDeleteItemCode; // Track which item is being checked for deletion

  List<CategoryModel> _categoriesForFilter = [];
  List<_LocationOption> _locationsForFilter = [];

  String? _appliedLocationId;
  final Set<String> _appliedCategoryCodes = {};
  final Map<String, String> _appliedAttributeFilters = {};
  final Map<String, int> _appliedAttributeTypes = {};

  @override
  void initState() {
    super.initState();
    _fetchItems();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _normalizeForSearch(String input) {
    final lower = input.trim().toLowerCase();
    final noSpace = lower.replaceAll(RegExp(r'[\s\u00A0]+'), '');
    return noSpace.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  bool get _filterActive =>
      (_appliedLocationId != null && _appliedLocationId!.trim().isNotEmpty) ||
      _appliedCategoryCodes.isNotEmpty ||
      _appliedAttributeFilters.isNotEmpty;

  bool get _showLocationFilterControls => _locationsForFilter.isNotEmpty;

  /// Items with no `location_id`, empty value, or an id that does not match any loaded location.
  bool _itemMatchesDefaultLocationFilter(ItemModel item) {
    final id = (item.locationId ?? '').trim();
    if (id.isEmpty) return true;
    return !_locationsForFilter.any((l) => l.id == id);
  }

  List<ItemModel> get _visibleItems {
    Iterable<ItemModel> list = _items;
    if (_filterActive) {
      final loc = _appliedLocationId?.trim();
      if (loc != null && loc.isNotEmpty) {
        if (loc == _defaultLocationFilterValue) {
          list = list.where(_itemMatchesDefaultLocationFilter);
        } else {
          list = list.where((i) => (i.locationId ?? '').trim() == loc);
        }
      }
      if (_appliedCategoryCodes.isNotEmpty) {
        list = list.where((i) => _appliedCategoryCodes.contains(i.categoryCode));
      }
      if (_appliedAttributeFilters.isNotEmpty) {
        list = list.where(
          (i) => itemMatchesAttributeFilters(
            i,
            _appliedAttributeFilters,
            _appliedAttributeTypes,
          ),
        );
      }
    }
    final query = _normalizeForSearch(_searchQuery);
    if (query.isEmpty) return list.toList();
    return list.where((item) {
      final normalizedName = _normalizeForSearch(item.name);
      final normalizedCode = _normalizeForSearch(item.code);
      return normalizedName.contains(query) || normalizedCode.contains(query);
    }).toList();
  }

  String _filterStatusSummary() {
    final parts = <String>[];
    if (_appliedCategoryCodes.isNotEmpty) {
      final names = _categoriesForFilter
          .where((c) => _appliedCategoryCodes.contains(c.code))
          .map((c) => c.name)
          .join(', ');
      parts.add('Category: ${names.isEmpty ? _appliedCategoryCodes.join(', ') : names}');
    }
    final locId = _appliedLocationId?.trim();
    if (locId != null && locId.isNotEmpty) {
      if (locId == _defaultLocationFilterValue) {
        parts.add('Location: Default (no location assigned)');
      } else {
        String locName = locId;
        for (final l in _locationsForFilter) {
          if (l.id == locId) {
            locName = l.name;
            break;
          }
        }
        parts.add('Location: $locName');
      }
    }
    for (final e in _appliedAttributeFilters.entries) {
      if (e.value.isEmpty) continue;
      if (e.key.endsWith('_from') || e.key.endsWith('_to')) {
        try {
          final d = DateTime.parse(e.value);
          final label = e.key.endsWith('_from') ? 'from' : 'to';
          parts.add('${e.key} ($label: ${DateFormat('dd MMM yyyy').format(d)})');
        } catch (_) {
          parts.add('${e.key}: ${e.value}');
        }
      } else {
        parts.add('${e.key}: ${e.value}');
      }
    }
    return parts.join(' | ');
  }

  Future<void> _fetchItems() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      debugPrint('Fetching items for user: ${widget.userId}');

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
      _userDocumentId = userDocumentId;

      // Fetch items directly from users/{userId}/items subcollection
      debugPrint('Fetching items from users/$userDocumentId/items');

      final itemsFuture = _firestore
          .collection('users')
          .doc(userDocumentId)
          .collection('items')
          .get();
      final categoriesFuture = _firestore
          .collection('users')
          .doc(userDocumentId)
          .collection('categories')
          .get();
      final locationsFuture = _firestore
          .collection('users')
          .doc(userDocumentId)
          .collection('locations')
          .get();

      final results = await Future.wait([
        itemsFuture,
        categoriesFuture,
        locationsFuture,
      ]);
      final itemsSnapshot = results[0] as QuerySnapshot;
      final categoriesSnapshot = results[1] as QuerySnapshot;
      final locationsSnapshot = results[2] as QuerySnapshot;

      debugPrint('Found ${itemsSnapshot.docs.length} items');

      final List<ItemModel> allItems = [];

      for (var itemDoc in itemsSnapshot.docs) {
        try {
          final item = ItemModel.fromFirestore(itemDoc);
          allItems.add(item);
        } catch (e) {
          debugPrint('Error parsing item ${itemDoc.id}: $e');
        }
      }

      final List<CategoryModel> cats = [];
      for (final d in categoriesSnapshot.docs) {
        try {
          cats.add(CategoryModel.fromFirestore(d));
        } catch (e) {
          debugPrint('Error parsing category ${d.id}: $e');
        }
      }
      cats.sort((a, b) => naturalSortComparator(a.name, b.name));

      final List<_LocationOption> locs = [];
      for (final d in locationsSnapshot.docs) {
        final data = d.data() as Map<String, dynamic>?;
        if (data == null) continue;
        final name = (data['name'] ?? '').toString().trim();
        locs.add(_LocationOption(id: d.id, name: name.isEmpty ? d.id : name));
      }
      locs.sort((a, b) => naturalSortComparator(a.name, b.name));

      // Sort items by name
      allItems.sort((a, b) {
        return a.name.compareTo(b.name);
      });

      final itemMappingsByCode = await _fetchItemMappingsByCode(userDocumentId);

      setState(() {
        _items = allItems;
        _itemMappingsByCode = itemMappingsByCode;
        _categoriesForFilter = cats;
        _locationsForFilter = locs;
        _isLoading = false;
      });

      debugPrint('Successfully loaded ${allItems.length} items');
    } catch (e) {
      debugPrint('Error fetching items: $e');
      setState(() {
        _errorMessage = 'Error fetching items: $e';
        _isLoading = false;
      });
    }
  }

  CategoryModel? _categoryByCode(String code) {
    for (final c in _categoriesForFilter) {
      if (c.code == code) return c;
    }
    return null;
  }

  /// Top-level categories (`parent_code` empty). Falls back to all active categories if none.
  List<CategoryModel> get _parentCategoriesForDropdown {
    final roots = _categoriesForFilter
        .where((c) => c.active && c.parentCode.trim().isEmpty)
        .toList();
    roots.sort((a, b) => naturalSortComparator(a.name, b.name));
    if (roots.isNotEmpty) return roots;
    final flat = _categoriesForFilter.where((c) => c.active).toList()
      ..sort((a, b) => naturalSortComparator(a.name, b.name));
    return flat;
  }

  List<CategoryModel> _subcategoriesForParentCode(String parentCode) {
    final subs = _categoriesForFilter
        .where((c) => c.active && c.parentCode == parentCode)
        .toList();
    subs.sort((a, b) => naturalSortComparator(a.name, b.name));
    return subs;
  }

  /// Resolved label for an item's location, or a fallback when ids exist but no match.
  String _locationLabelForItem(ItemModel item) {
    final id = (item.locationId ?? '').trim();
    if (id.isEmpty) return '—';
    for (final l in _locationsForFilter) {
      if (l.id == id) return l.name;
    }
    return id;
  }

  Future<Map<String, List<Map<String, dynamic>>>> _fetchItemMappingsByCode(
    String userDocumentId,
  ) async {
    final grouped = <String, List<Map<String, dynamic>>>{};
    try {
      final mappingsSnapshot = await _firestore
          .collection('users')
          .doc(userDocumentId)
          .collection('item_mappings')
          .get();

      for (final doc in mappingsSnapshot.docs) {
        final data = doc.data();
        final itemCode = (data['item_code'] ?? '').toString().trim();
        if (itemCode.isEmpty) continue;
        grouped.putIfAbsent(itemCode, () => []);
        grouped[itemCode]!.add({'doc_id': doc.id, ...data});
      }
    } catch (e) {
      debugPrint('Error fetching item mappings: $e');
    }
    return grouped;
  }

  void _rebuildDialogAttributeMaps(
    List<CategoryModel> selected,
    Map<String, List<String>> categoryAttrsOut,
    Map<String, int> attributeTypesOut,
    Map<String, String?> selectedAttrs,
  ) {
    categoryAttrsOut.clear();
    attributeTypesOut.clear();
    if (selected.length != 1) return;
    final cat = selected.first;
    if (cat.attributeTypes.isNotEmpty) {
      try {
        final typesMap = jsonDecode(cat.attributeTypes) as Map<String, dynamic>;
        typesMap.forEach((k, v) {
          attributeTypesOut[k] = v is int ? v : int.tryParse(v.toString()) ?? 1;
        });
      } catch (e) {
        debugPrint('attributeTypes parse: $e');
      }
    }
    if (cat.attributes.isEmpty) return;
    try {
      final attrsMap = jsonDecode(cat.attributes) as Map<String, dynamic>;
      attrsMap.forEach((key, value) {
        final attrType = attributeTypesOut[key] ?? 1;
        if (value is! Map<String, dynamic>) return;
        if (attrType == 3 || attrType == 4) {
          selectedAttrs.putIfAbsent(key, () => null);
        } else {
          final vals = value.entries
              .where((e) => e.value == true)
              .map((e) => e.key)
              .toList();
          if (vals.isNotEmpty) {
            vals.sort(naturalSortComparator);
            categoryAttrsOut[key] = vals;
          }
        }
      });
    } catch (e) {
      debugPrint('attributes parse: $e');
    }
  }

  Future<void> _showFilterItemsDialog() async {
    String? dialogParentCode;
    String? dialogLeafCode;

    if (_appliedCategoryCodes.length == 1) {
      final code = _appliedCategoryCodes.first;
      final cat = _categoryByCode(code);
      if (cat != null) {
        if (cat.parentCode.trim().isNotEmpty) {
          dialogParentCode = cat.parentCode;
          dialogLeafCode = cat.code;
        } else {
          dialogParentCode = cat.code;
          dialogLeafCode = null;
        }
      }
    }

    String? dialogLocationId = _appliedLocationId;
    final dialogCategoryAttributes = <String, List<String>>{};
    final dialogAttributeTypes = <String, int>{};
    final dialogSelectedAttributes = <String, String?>{}
      ..addAll(_appliedAttributeFilters.map((k, v) => MapEntry(k, v)));

    CategoryModel? effectiveCategoryForDialog() {
      if (dialogParentCode == null) return null;
      final parent = _categoryByCode(dialogParentCode!);
      if (parent == null) return null;
      final subs = _subcategoriesForParentCode(parent.code);
      if (subs.isEmpty) return parent;
      if (dialogLeafCode == null) return null;
      return _categoryByCode(dialogLeafCode!);
    }

    void syncAttrMaps() {
      dialogCategoryAttributes.clear();
      dialogAttributeTypes.clear();
      final eff = effectiveCategoryForDialog();
      if (eff == null) {
        dialogSelectedAttributes.clear();
        return;
      }
      _rebuildDialogAttributeMaps(
        [eff],
        dialogCategoryAttributes,
        dialogAttributeTypes,
        dialogSelectedAttributes,
      );
      final keep = <String>{};
      for (final k in dialogCategoryAttributes.keys) {
        keep.add(k);
      }
      for (final e in dialogAttributeTypes.entries) {
        keep.add(e.key);
        if (e.value == 4) {
          keep.add('${e.key}_from');
          keep.add('${e.key}_to');
        }
      }
      dialogSelectedAttributes.removeWhere((k, _) => !keep.contains(k));
    }

    syncAttrMaps();

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              insetPadding: const EdgeInsets.all(16),
              child: SizedBox(
                width: MediaQuery.of(ctx).size.width * 0.9,
                height: MediaQuery.of(ctx).size.height * 0.88,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.filter_list, color: Theme.of(ctx).colorScheme.primary),
                          const SizedBox(width: 8),
                          const Text(
                            'Filter Items',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Category',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(ctx).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            InputDecorator(
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                labelText: 'Select category',
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String?>(
                                  isExpanded: true,
                                  value: dialogParentCode,
                                  hint: const Text('Select category'),
                                  items: [
                                    const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('None'),
                                    ),
                                    ..._parentCategoriesForDropdown.map(
                                      (c) => DropdownMenuItem<String?>(
                                        value: c.code,
                                        child: Text(c.name),
                                      ),
                                    ),
                                  ],
                                  onChanged: (v) {
                                    setDialogState(() {
                                      dialogParentCode = v;
                                      dialogLeafCode = null;
                                      syncAttrMaps();
                                    });
                                  },
                                ),
                              ),
                            ),
                            Builder(
                              builder: (context) {
                                if (dialogParentCode == null) return const SizedBox.shrink();
                                final parent = _categoryByCode(dialogParentCode!);
                                if (parent == null) return const SizedBox.shrink();
                                final subs = _subcategoriesForParentCode(parent.code);
                                if (subs.isEmpty) return const SizedBox.shrink();
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 20),
                                    Text(
                                      'Subcategory',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(ctx).colorScheme.primary,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    InputDecorator(
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                        labelText: 'Select subcategory',
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String?>(
                                          isExpanded: true,
                                          value: dialogLeafCode,
                                          hint: const Text('Select subcategory'),
                                          items: subs
                                              .map(
                                                (c) => DropdownMenuItem<String?>(
                                                  value: c.code,
                                                  child: Text(c.name),
                                                ),
                                              )
                                              .toList(),
                                          onChanged: (v) {
                                            setDialogState(() {
                                              dialogLeafCode = v;
                                              syncAttrMaps();
                                            });
                                          },
                                        ),
                                      ),
                                    ),
                                    if (dialogLeafCode == null) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        'Choose a subcategory to filter items and set attributes.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),
                            if (_showLocationFilterControls) ...[
                              const SizedBox(height: 20),
                              Text(
                                'Location',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(ctx).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              InputDecorator(
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String?>(
                                    isExpanded: true,
                                    value: dialogLocationId,
                                    hint: const Text('All locations'),
                                    items: [
                                      const DropdownMenuItem<String?>(
                                        value: null,
                                        child: Text('All locations'),
                                      ),
                                      DropdownMenuItem<String?>(
                                        value: _defaultLocationFilterValue,
                                        child: const Text(
                                          'Default — no location assigned',
                                        ),
                                      ),
                                      ..._locationsForFilter.map(
                                        (l) => DropdownMenuItem<String?>(
                                          value: l.id,
                                          child: Text(l.name),
                                        ),
                                      ),
                                    ],
                                    onChanged: (v) => setDialogState(() => dialogLocationId = v),
                                  ),
                                ),
                              ),
                            ],
                            if (effectiveCategoryForDialog() != null) ...[
                              const SizedBox(height: 20),
                              Text(
                                'Select attributes',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(ctx).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...() {
                                final entries = dialogCategoryAttributes.entries.toList()
                                  ..sort((a, b) => naturalSortComparator(a.key, b.key));
                                return entries.map((entry) {
                                  final key = entry.key;
                                  final type = dialogAttributeTypes[key] ?? 1;
                                  final multi = type == 2;
                                  final opts = entry.value;
                                  final cur = dialogSelectedAttributes[key];
                                  if (multi) {
                                    final selectedSet = (cur ?? '')
                                        .split(',')
                                        .map((s) => s.trim())
                                        .where((s) => s.isNotEmpty)
                                        .toSet();
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(key, style: const TextStyle(fontWeight: FontWeight.w500)),
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 6,
                                            children: opts.map((opt) {
                                              final on = selectedSet.contains(opt);
                                              return FilterChip(
                                                label: Text(opt),
                                                selected: on,
                                                onSelected: (v) {
                                                  setDialogState(() {
                                                    if (v) {
                                                      selectedSet.add(opt);
                                                    } else {
                                                      selectedSet.remove(opt);
                                                    }
                                                    dialogSelectedAttributes[key] = selectedSet.isEmpty
                                                        ? null
                                                        : selectedSet.join(',');
                                                  });
                                                },
                                              );
                                            }).toList(),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: DropdownButtonFormField<String?>(
                                      key: ValueKey('attr_sel_$key'),
                                      initialValue: cur,
                                      decoration: InputDecoration(
                                        labelText: key,
                                        border: const OutlineInputBorder(),
                                      ),
                                      items: [
                                        const DropdownMenuItem<String?>(
                                          value: null,
                                          child: Text('Any'),
                                        ),
                                        ...opts.map(
                                          (o) => DropdownMenuItem<String?>(value: o, child: Text(o)),
                                        ),
                                      ],
                                      onChanged: (v) {
                                        setDialogState(() {
                                          dialogSelectedAttributes[key] = v;
                                        });
                                      },
                                    ),
                                  );
                                }).toList();
                              }(),
                              ...() {
                                final textDateKeys = dialogAttributeTypes.entries
                                    .where((e) => e.value == 3 || e.value == 4)
                                    .map((e) => e.key)
                                    .toList()
                                  ..sort(naturalSortComparator);
                                return textDateKeys.map<Widget>((attrName) {
                                  final t = dialogAttributeTypes[attrName] ?? 1;
                                  if (t == 3) {
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: TextFormField(
                                        key: ValueKey('attr_txt_$attrName'),
                                        initialValue: dialogSelectedAttributes[attrName] ?? '',
                                        decoration: InputDecoration(
                                          labelText: attrName,
                                          border: const OutlineInputBorder(),
                                        ),
                                        onChanged: (v) {
                                          dialogSelectedAttributes[attrName] =
                                              v.trim().isEmpty ? null : v.trim();
                                        },
                                      ),
                                    );
                                  }
                                  final fromKey = '${attrName}_from';
                                  final toKey = '${attrName}_to';
                                  DateTime? parseD(String? s) {
                                    if (s == null || s.isEmpty) return null;
                                    try {
                                      return DateTime.parse(s);
                                    } catch (_) {
                                      return null;
                                    }
                                  }

                                  final fromD = parseD(dialogSelectedAttributes[fromKey]);
                                  final toD = parseD(dialogSelectedAttributes[toKey]);

                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: Text('$attrName (from)'),
                                        subtitle: Text(
                                          fromD != null ? DateFormat('dd MMM yyyy').format(fromD) : '—',
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.calendar_today),
                                              onPressed: () async {
                                                final picked = await showDatePicker(
                                                  context: ctx,
                                                  initialDate: fromD ?? DateTime.now(),
                                                  firstDate: DateTime(2000),
                                                  lastDate: DateTime(2100),
                                                );
                                                if (picked != null) {
                                                  setDialogState(() {
                                                    dialogSelectedAttributes[fromKey] =
                                                        picked.toIso8601String();
                                                  });
                                                }
                                              },
                                            ),
                                            if (fromD != null)
                                              IconButton(
                                                icon: const Icon(Icons.clear),
                                                onPressed: () {
                                                  setDialogState(() {
                                                    dialogSelectedAttributes[fromKey] = null;
                                                  });
                                                },
                                              ),
                                          ],
                                        ),
                                      ),
                                      ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: Text('$attrName (to)'),
                                        subtitle: Text(
                                          toD != null ? DateFormat('dd MMM yyyy').format(toD) : '—',
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.calendar_today),
                                              onPressed: () async {
                                                final picked = await showDatePicker(
                                                  context: ctx,
                                                  initialDate: toD ?? fromD ?? DateTime.now(),
                                                  firstDate: fromD ?? DateTime(2000),
                                                  lastDate: DateTime(2100),
                                                );
                                                if (picked != null) {
                                                  setDialogState(() {
                                                    dialogSelectedAttributes[toKey] =
                                                        picked.toIso8601String();
                                                  });
                                                }
                                              },
                                            ),
                                            if (toD != null)
                                              IconButton(
                                                icon: const Icon(Icons.clear),
                                                onPressed: () {
                                                  setDialogState(() {
                                                    dialogSelectedAttributes[toKey] = null;
                                                  });
                                                },
                                              ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                  );
                                }).toList();
                              }(),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _appliedLocationId = null;
                                _appliedCategoryCodes.clear();
                                _appliedAttributeFilters.clear();
                                _appliedAttributeTypes.clear();
                              });
                              Navigator.pop(ctx);
                            },
                            child: const Text('Clear all'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton(
                            onPressed: () {
                              final hasLoc =
                                  dialogLocationId != null && dialogLocationId!.trim().isNotEmpty;
                              final eff = effectiveCategoryForDialog();
                              final hasCat = eff != null;
                              if (!hasLoc && !hasCat) {
                                setState(() {
                                  _appliedLocationId = null;
                                  _appliedCategoryCodes.clear();
                                  _appliedAttributeFilters.clear();
                                  _appliedAttributeTypes.clear();
                                });
                                Navigator.pop(ctx);
                                return;
                              }
                              setState(() {
                                _appliedLocationId = dialogLocationId?.trim().isEmpty == true
                                    ? null
                                    : dialogLocationId?.trim();
                                _appliedCategoryCodes.clear();
                                if (eff != null) {
                                  _appliedCategoryCodes.add(eff.code);
                                }
                                _appliedAttributeFilters.clear();
                                _appliedAttributeTypes.clear();
                                if (eff != null) {
                                  dialogSelectedAttributes.forEach((k, v) {
                                    if (v != null && v.isNotEmpty) {
                                      _appliedAttributeFilters[k] = v;
                                    }
                                  });
                                  _appliedAttributeTypes.addAll(dialogAttributeTypes);
                                }
                              });
                              Navigator.pop(ctx);
                            },
                            child: const Text('Apply'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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
            const Text('Items'),
            if (!_isLoading && _items.isNotEmpty)
              Text(
                (_filterActive || _normalizeForSearch(_searchQuery).isNotEmpty)
                    ? '${_visibleItems.length} / ${_items.length} items'
                    : '${_items.length} item${_items.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Filter by location & category',
            onPressed: _showFilterItemsDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _fetchItems,
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
                      onPressed: _fetchItems,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : _items.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No items found',
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
              onRefresh: _fetchItems,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _showFilterItemsDialog,
                        icon: const Icon(Icons.tune, size: 18),
                        label: const Text('Filter items'),
                      ),
                    ),
                  ),
                  if (_filterActive)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                      child: Material(
                        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              Icon(
                                Icons.filter_list,
                                size: 18,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _filterStatusSummary(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                tooltip: 'Clear filters',
                                onPressed: () {
                                  setState(() {
                                    _appliedLocationId = null;
                                    _appliedCategoryCodes.clear();
                                    _appliedAttributeFilters.clear();
                                    _appliedAttributeTypes.clear();
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search by item name or code',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchQuery.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setState(() {
                                    _searchController.clear();
                                    _searchQuery = '';
                                  });
                                },
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: _visibleItems.isEmpty
                        ? Center(
                            child: Text(
                              'No items match the current filters or search',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 15,
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16.0),
                            itemCount: _visibleItems.length,
                            itemBuilder: (context, index) {
                              return _buildItemCard(_visibleItems[index]);
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildItemCard(ItemModel item) {
    final mappings = _itemMappingsByCode[item.code] ?? const [];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showItemDetailsModal(item),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.orange[100],
                    child: Icon(Icons.inventory_2, color: Colors.orange[700]),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Code: ${item.code}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_checkingDeleteItemCode == item.code)
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _handleDeleteItem(item),
                      tooltip: 'Delete item',
                    ),
                  Icon(Icons.chevron_right, color: Colors.grey[400]),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    label: Text('Category: ${item.categoryCode}'),
                    backgroundColor: Colors.blue[50],
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    labelStyle: const TextStyle(fontSize: 12),
                  ),
                  if (_locationsForFilter.isNotEmpty)
                    Chip(
                      avatar: Icon(
                        Icons.place_outlined,
                        size: 16,
                        color: Colors.purple[700],
                      ),
                      label: Text(
                        'Location: ${_locationLabelForItem(item)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      backgroundColor: Colors.purple[50],
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                    ),
                  Chip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.printed ? Icons.check_circle : Icons.cancel,
                          size: 14,
                          color: item.printed ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 4),
                        Text(item.printed ? 'Printed' : 'Not Printed'),
                      ],
                    ),
                    backgroundColor: item.printed
                        ? Colors.green[50]
                        : Colors.red[50],
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    labelStyle: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.schedule, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Created: ${_formatDateTime(item.createdAt)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.update, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Updated: ${_formatDateTime(item.updatedAt)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                ],
              ),
              if (mappings.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Mapped Info (${mappings.length})',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                ...mappings.map((mapping) {
                  final mapCode = (mapping['map_code'] ?? '').toString();
                  final itemId = (mapping['item_id'] ?? '').toString();
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.teal[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.teal.shade100),
                    ),
                    child: Text(
                      'Map Code: ${mapCode.isEmpty ? '-' : mapCode} | Item ID: ${itemId.isEmpty ? '-' : itemId}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.teal.shade900,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showItemDetailsModal(ItemModel item) {
    // Parse attributes JSON string
    Map<String, dynamic>? parsedAttributes;
    if (item.attributes.isNotEmpty) {
      try {
        parsedAttributes = jsonDecode(item.attributes) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('Error parsing attributes: $e');
      }
    }

    final mappings = _itemMappingsByCode[item.code] ?? const [];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.orange[100],
                      radius: 24,
                      child: Icon(Icons.inventory_2, color: Colors.orange[700]),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Code: ${item.code}',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: 'Edit',
                      onPressed: () {
                        Navigator.pop(context);
                        _showEditItemDialog(item);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(),
              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    _buildDetailRow('Name', item.name),
                    _buildDetailRow('Code', item.code),
                    _buildDetailRow('Category Code', item.categoryCode),
                    _buildDetailRow(
                      'Price',
                      '₹${item.price.toStringAsFixed(2)}',
                    ),
                    _buildDetailRow(
                      'Sell Price',
                      '₹${item.sellPrice.toStringAsFixed(2)}',
                    ),
                    _buildDetailRow('Quantity', item.quantity.toString()),
                    _buildDetailRow(
                      'Available Quantity',
                      item.availableQty.toString(),
                    ),
                    _buildDetailRow(
                      'Archived Quantity',
                      item.archivedQty.toString(),
                    ),
                    _buildDetailRow('Unit', item.unit),
                    if (item.taxPerc != null)
                      _buildDetailRow(
                        'Tax %',
                        '${item.taxPerc!.toStringAsFixed(2)}%',
                      ),
                    if (item.hsnCode != null && item.hsnCode!.isNotEmpty)
                      _buildDetailRow('HSN Code', item.hsnCode!),
                    if (item.description != null &&
                        item.description!.isNotEmpty)
                      _buildDetailRow('Description', item.description!),
                    if (item.scannedBarcode != null &&
                        item.scannedBarcode!.isNotEmpty)
                      _buildDetailRow('Scanned Barcode', item.scannedBarcode!),
                    if (item.additionalInfo.isNotEmpty)
                      _buildDetailRow('Additional Info', item.additionalInfo),
                    _buildDetailRow(
                      'Status',
                      item.active ? 'Active' : 'Inactive',
                    ),
                    _buildDetailRow('Printed', item.printed ? 'Yes' : 'No'),
                    _buildDetailRow('Mapped', item.mapped ? 'Yes' : 'No'),
                    _buildDetailRow(
                      'Listed Online',
                      item.listedOnline ? 'Yes' : 'No',
                    ),
                    if (item.slNo != null)
                      _buildDetailRow('SL No', item.slNo.toString()),
                    _buildDetailRow(
                      'Created At',
                      _formatDateTime(item.createdAt),
                    ),
                    _buildDetailRow(
                      'Updated At',
                      _formatDateTime(item.updatedAt),
                    ),
                    if (parsedAttributes != null &&
                        parsedAttributes.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Attributes',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: parsedAttributes.entries.map((entry) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 100,
                                    child: Text(
                                      '${entry.key}:',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      entry.value.toString(),
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ] else if (item.attributes.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Attributes (Raw)',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Text(
                          item.attributes,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                    if (mappings.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Mapped Info',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...mappings.map((mapping) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.teal[50],
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.teal.shade100),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: mapping.entries.map((entry) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  '${entry.key}: ${entry.value}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              );
                            }).toList(),
                          ),
                        );
                      }),
                    ] else ...[
                      const SizedBox(height: 16),
                      _buildDetailRow('Mapped Info', 'No mappings found'),
                    ],
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
                fontSize: 14,
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  void _showEditItemDialog(ItemModel item) {
    showDialog(
      context: context,
      builder: (context) => EditItemDialog(
        item: item,
        userId: widget.userId,
        onUpdated: () {
          _fetchItems();
        },
      ),
    );
  }

  Future<String?> _getUserDocumentId() async {
    try {
      if (_userDocumentId != null && _userDocumentId!.isNotEmpty) {
        return _userDocumentId;
      }
      // Try to find user by userId field
      final userQuery = await _firestore
          .collection('users')
          .where('userId', isEqualTo: widget.userId)
          .limit(1)
          .get();

      if (userQuery.docs.isNotEmpty) {
        _userDocumentId = userQuery.docs.first.id;
        return _userDocumentId;
      }

      // Try by document ID
      final userDoc = await _firestore
          .collection('users')
          .doc(widget.userId)
          .get();

      if (userDoc.exists) {
        _userDocumentId = widget.userId;
        return _userDocumentId;
      }

      return null;
    } catch (e) {
      debugPrint('Error getting user document ID: $e');
      return null;
    }
  }

  Future<int> _checkItemInBills(String itemCode) async {
    try {
      final userDocumentId = await _getUserDocumentId();

      if (userDocumentId == null) {
        return 0;
      }

      // Fetch all bills for the user
      final billsSnapshot = await _firestore
          .collection('users')
          .doc(userDocumentId)
          .collection('bills')
          .get();

      int billCount = 0;

      // Check each bill for the item code
      for (var billDoc in billsSnapshot.docs) {
        final billData = billDoc.data();

        // Check if bill has items array
        if (billData.containsKey('items') && billData['items'] != null) {
          final items = billData['items'];
          if (items is List) {
            // Items stored as array
            for (var item in items) {
              if (item is Map<String, dynamic>) {
                final itemCodeInBill = item['code']?.toString() ?? '';
                if (itemCodeInBill == itemCode) {
                  billCount++;
                  break; // Found in this bill, move to next bill
                }
              }
            }
          }
        }

        // Also check bill_items subcollection if it exists
        try {
          final billItemsSnapshot = await _firestore
              .collection('users')
              .doc(userDocumentId)
              .collection('bills')
              .doc(billDoc.id)
              .collection('bill_items')
              .where('code', isEqualTo: itemCode)
              .limit(1)
              .get();

          if (billItemsSnapshot.docs.isNotEmpty) {
            billCount++;
          }
        } catch (e) {
          // Subcollection might not exist, that's okay
          debugPrint('Error checking bill_items subcollection: $e');
        }
      }

      return billCount;
    } catch (e) {
      debugPrint('Error checking item in bills: $e');
      return 0;
    }
  }

  Future<void> _handleDeleteItem(ItemModel item) async {
    // Set loading state
    setState(() {
      _checkingDeleteItemCode = item.code;
    });

    try {
      // Check if item is used in any bills
      final billCount = await _checkItemInBills(item.code);

      // Clear loading state
      setState(() {
        _checkingDeleteItemCode = null;
      });

      if (billCount > 0) {
        // Show error dialog
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Cannot Delete Item'),
              content: Text(
                'This item is being used in $billCount bill${billCount == 1 ? '' : 's'}. '
                'Items that are used in bills cannot be deleted.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }

      if (!mounted) return;

      // No bills using it, show confirmation dialog
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Item'),
          content: Text('Are you sure you want to delete "${item.name}"?'),
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
        await _deleteItem(item);
      }
    } catch (e) {
      // Clear loading state on error
      setState(() {
        _checkingDeleteItemCode = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error checking item: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteItem(ItemModel item) async {
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

      // Find item document by code
      final itemsQuery = await _firestore
          .collection('users')
          .doc(userDocumentId)
          .collection('items')
          .where('code', isEqualTo: item.code)
          .limit(1)
          .get();

      if (itemsQuery.docs.isNotEmpty) {
        // Delete the document
        await itemsQuery.docs.first.reference.delete();
      } else {
        // Try using code as document ID
        await _firestore
            .collection('users')
            .doc(userDocumentId)
            .collection('items')
            .doc(item.code)
            .delete();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Item deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _fetchItems();
      }
    } catch (e) {
      debugPrint('Error deleting item: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting item: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
