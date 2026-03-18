import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/category_model.dart';
import '../models/item_model.dart';

class EditItemDialog extends StatefulWidget {
  final ItemModel item;
  final String userId;
  final VoidCallback onUpdated;

  const EditItemDialog({
    super.key,
    required this.item,
    required this.userId,
    required this.onUpdated,
  });

  @override
  State<EditItemDialog> createState() => _EditItemDialogState();
}

class _EditItemDialogState extends State<EditItemDialog> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _sellPriceController = TextEditingController();
  final TextEditingController _hsnController = TextEditingController();
  final TextEditingController _taxPercController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _unitController = TextEditingController();

  // State
  List<CategoryModel> _categories = [];
  CategoryModel? _selectedCategory;
  bool _isLoadingCategories = true;
  bool _isSaving = false;

  // Dynamic attributes
  Map<String, List<String>> _categoryAttributes = {};
  Map<String, String?> _selectedAttributes = {};
  Map<String, int> _attributeTypes = {};
  Map<String, TextEditingController> _textFieldControllers = {};

  // HSN warning
  bool _showHsnWarning = false;

  @override
  void initState() {
    super.initState();
    _initializeFields();
    _loadCategories();
  }

  // Store item attributes temporarily to load after category attributes
  Map<String, dynamic> _itemAttributes = {};

  void _initializeFields() {
    _nameController.text = widget.item.name;
    _priceController.text = widget.item.price.toStringAsFixed(2);
    _quantityController.text = widget.item.quantity.toStringAsFixed(2);
    _sellPriceController.text = widget.item.sellPrice.toStringAsFixed(2);
    _hsnController.text = widget.item.hsnCode ?? '';
    _taxPercController.text = widget.item.taxPerc?.toStringAsFixed(2) ?? '0.0';
    _descriptionController.text = widget.item.description ?? '';
    _unitController.text = widget.item.unit;

    // Store item attributes temporarily (will be loaded after category attributes)
    if (widget.item.attributes.isNotEmpty) {
      try {
        _itemAttributes = jsonDecode(widget.item.attributes);
      } catch (e) {
        debugPrint('Error parsing item attributes: $e');
        _itemAttributes = {};
      }
    }

    // Listen to HSN changes
    _hsnController.addListener(_checkHsnWarning);
  }

  void _checkHsnWarning() {
    final trimmedHsn = _hsnController.text.trim();
    if (_selectedCategory != null && trimmedHsn.length >= 6) {
      final categoryHsn = _selectedCategory!.hsnCode.trim();
      final hsnPrefix = trimmedHsn.substring(0, 6).toLowerCase();
      final categoryPrefix = categoryHsn.length >= 6
          ? categoryHsn.substring(0, 6).toLowerCase()
          : categoryHsn.toLowerCase();
      setState(() {
        _showHsnWarning = categoryPrefix != hsnPrefix;
      });
    } else {
      setState(() {
        _showHsnWarning = false;
      });
    }
  }

  Future<void> _loadCategories() async {
    try {
      // Find user document
      String? userDocumentId;
      final userQuery = await _firestore
          .collection('users')
          .where('userId', isEqualTo: widget.userId)
          .limit(1)
          .get();

      if (userQuery.docs.isNotEmpty) {
        userDocumentId = userQuery.docs.first.id;
      } else {
        final userDoc = await _firestore
            .collection('users')
            .doc(widget.userId)
            .get();
        if (userDoc.exists) {
          userDocumentId = widget.userId;
        }
      }

      if (userDocumentId == null) {
        setState(() {
          _isLoadingCategories = false;
        });
        return;
      }

      // Fetch categories
      final categoriesSnapshot = await _firestore
          .collection('users')
          .doc(userDocumentId)
          .collection('categories')
          .get();

      final categories = categoriesSnapshot.docs
          .map((doc) => CategoryModel.fromFirestore(doc))
          .toList();

      categories.sort((a, b) => a.name.compareTo(b.name));

      setState(() {
        _categories = categories;
        _isLoadingCategories = false;

        // Select the item's category - only if found in the list
        try {
          _selectedCategory = categories.firstWhere(
            (cat) => cat.code == widget.item.categoryCode,
          );
        } catch (e) {
          // Category not found, set to first category if available, or null
          _selectedCategory = categories.isNotEmpty ? categories.first : null;
        }

        if (_selectedCategory != null) {
          _loadCategoryAttributes(_selectedCategory!);
        }
      });
    } catch (e) {
      debugPrint('Error loading categories: $e');
      setState(() {
        _isLoadingCategories = false;
      });
    }
  }

  void _loadCategoryAttributes(CategoryModel category) {
    _categoryAttributes.clear();
    _attributeTypes.clear();
    _selectedAttributes.clear();
    _textFieldControllers.clear();

    if (category.attributes.isNotEmpty) {
      try {
        final Map<String, dynamic> attrsMap = jsonDecode(category.attributes);

        // Load attribute types first
        if (category.attributeTypes.isNotEmpty) {
          try {
            final Map<String, dynamic> typesMap = jsonDecode(
              category.attributeTypes,
            );
            _attributeTypes = typesMap.map((key, value) {
              final intType = value is int
                  ? value
                  : int.tryParse(value.toString()) ?? 1;
              return MapEntry(key, intType);
            });
          } catch (e) {
            debugPrint('Error parsing attributeTypes: $e');
          }
        }

        // Step 1: Load ALL category attribute values first
        attrsMap.forEach((key, value) {
          final int attrType = _attributeTypes[key] ?? 1;

          if (value is Map<String, dynamic>) {
            if (attrType == 3) {
              // Text field - initialize controller with default, will be updated with item value
              final defaultText = value['default_text']?.toString() ?? '';
              _textFieldControllers[key] = TextEditingController(
                text: defaultText,
              );
            } else if (attrType == 4) {
              // Date field - will be handled when assigning item values
              // No default needed here
            } else {
              // Select field (type 1 or 2) - load ALL possible values
              final values = value.entries
                  .where((e) => e.value == true)
                  .map((e) => e.key)
                  .toList();
              if (values.isNotEmpty) {
                values.sort();
                _categoryAttributes[key] = values;
              }
            }
          }
        });

        // Step 2: Now assign item attribute values to fields
        _itemAttributes.forEach((key, value) {
          final int attrType = _attributeTypes[key] ?? 1;
          final valueStr = value?.toString();

          if (attrType == 3) {
            // Text field - update controller with item value
            if (_textFieldControllers.containsKey(key)) {
              _textFieldControllers[key]!.text = valueStr ?? '';
            } else {
              _textFieldControllers[key] = TextEditingController(
                text: valueStr ?? '',
              );
            }
            _selectedAttributes[key] = valueStr;
          } else if (attrType == 4) {
            // Date field - assign item value
            _selectedAttributes[key] = valueStr;
          } else {
            // Select field (type 1 or 2) - assign item value
            _selectedAttributes[key] = valueStr;
          }
        });

        // Step 3: For attributes that don't have item values, set defaults
        attrsMap.forEach((key, value) {
          if (!_selectedAttributes.containsKey(key)) {
            final int attrType = _attributeTypes[key] ?? 1;
            if (value is Map<String, dynamic>) {
              if (attrType == 3) {
                // Text field - use default
                final defaultText = value['default_text']?.toString() ?? '';
                _selectedAttributes[key] = defaultText;
                if (_textFieldControllers.containsKey(key)) {
                  _textFieldControllers[key]!.text = defaultText;
                }
              } else if (attrType == 4) {
                // Date field - use default
                final defaultDate =
                    value['default_date']?.toString() ??
                    value['start_date']?.toString() ??
                    value['end_date']?.toString();
                _selectedAttributes[key] = defaultDate;
              }
              // For select fields, no default needed - they start as null
            }
          }
        });
      } catch (e) {
        debugPrint('Error parsing category attributes: $e');
      }
    }

    setState(() {});
  }

  Future<void> _saveItem() async {
    if (!_formKey.currentState!.validate() || _selectedCategory == null) {
      return;
    }

    // Check HSN warning
    final trimmedHsn = _hsnController.text.trim();
    if (_selectedCategory != null && trimmedHsn.length >= 6) {
      final categoryHsn = _selectedCategory!.hsnCode.trim();
      final hsnPrefix = trimmedHsn.substring(0, 6).toLowerCase();
      final categoryPrefix = categoryHsn.length >= 6
          ? categoryHsn.substring(0, 6).toLowerCase()
          : categoryHsn.toLowerCase();
      if (categoryPrefix != hsnPrefix) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'HSN does not match selected category. Please correct it.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    setState(() {
      _isSaving = true;
    });

    try {
      // Find user document
      String? userDocumentId;
      final userQuery = await _firestore
          .collection('users')
          .where('userId', isEqualTo: widget.userId)
          .limit(1)
          .get();

      if (userQuery.docs.isNotEmpty) {
        userDocumentId = userQuery.docs.first.id;
      } else {
        final userDoc = await _firestore
            .collection('users')
            .doc(widget.userId)
            .get();
        if (userDoc.exists) {
          userDocumentId = widget.userId;
        }
      }

      if (userDocumentId == null) {
        throw Exception('User document not found');
      }

      // Update text field attributes
      _textFieldControllers.forEach((key, controller) {
        _selectedAttributes[key] = controller.text.trim();
      });

      // Build updated item
      final updatedItem = ItemModel(
        id: widget.item.id,
        code: widget.item.code,
        name: _nameController.text.trim(),
        categoryCode: _selectedCategory!.code,
        price: double.tryParse(_priceController.text) ?? widget.item.price,
        quantity:
            double.tryParse(_quantityController.text) ?? widget.item.quantity,
        availableQty: widget.item.availableQty,
        sellPrice:
            double.tryParse(_sellPriceController.text) ?? widget.item.sellPrice,
        hsnCode: _hsnController.text.trim().isNotEmpty
            ? _hsnController.text.trim()
            : null,
        taxPerc: _taxPercController.text.trim().isNotEmpty
            ? double.tryParse(_taxPercController.text)
            : null,
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        attributes: jsonEncode(_selectedAttributes),
        printed: widget.item.printed,
        mapped: widget.item.mapped,
        active: widget.item.active,
        unit: _unitController.text.trim().isNotEmpty
            ? _unitController.text.trim()
            : widget.item.unit,
        scannedBarcode: widget.item.scannedBarcode,
        listedOnline: widget.item.listedOnline,
        additionalInfo: widget.item.additionalInfo,
        createdAt: widget.item.createdAt,
        updatedAt: DateTime.now(),
      );

      // Find item document by code (since document ID might not be the code)
      final itemsQuery = await _firestore
          .collection('users')
          .doc(userDocumentId)
          .collection('items')
          .where('code', isEqualTo: widget.item.code)
          .limit(1)
          .get();

      if (itemsQuery.docs.isNotEmpty) {
        // Update existing document
        await itemsQuery.docs.first.reference.set(
          updatedItem.toMap(),
          SetOptions(merge: true),
        );
      } else {
        // If not found by query, try using code as document ID
        await _firestore
            .collection('users')
            .doc(userDocumentId)
            .collection('items')
            .doc(widget.item.code)
            .set(updatedItem.toMap(), SetOptions(merge: true));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Item updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onUpdated();
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error saving item: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving item: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _quantityController.dispose();
    _sellPriceController.dispose();
    _hsnController.dispose();
    _taxPercController.dispose();
    _descriptionController.dispose();
    _unitController.dispose();
    _textFieldControllers.values.forEach((c) => c.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                const Text(
                  'Edit Item',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(),
            // Form
            Flexible(
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Name *',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            value?.isEmpty ?? true ? 'Name is required' : null,
                      ),
                      const SizedBox(height: 16),
                      // Category
                      _isLoadingCategories
                          ? const CircularProgressIndicator()
                          : DropdownButtonFormField<CategoryModel>(
                              value:
                                  _selectedCategory != null &&
                                      _categories.any(
                                        (c) =>
                                            c.code == _selectedCategory!.code,
                                      )
                                  ? _selectedCategory
                                  : null,
                              decoration: const InputDecoration(
                                labelText: 'Category *',
                                border: OutlineInputBorder(),
                              ),
                              items: _categories.map((cat) {
                                return DropdownMenuItem(
                                  value: cat,
                                  child: Text(cat.name),
                                );
                              }).toList(),
                              onChanged: (cat) {
                                setState(() {
                                  _selectedCategory = cat;
                                  if (cat != null) {
                                    _hsnController.text = cat.hsnCode;
                                    _taxPercController.text = cat.taxPercentage
                                        .toStringAsFixed(2);
                                    _loadCategoryAttributes(cat);
                                    _checkHsnWarning();
                                  }
                                });
                              },
                              validator: (value) =>
                                  value == null ? 'Category is required' : null,
                            ),
                      const SizedBox(height: 16),
                      // Dynamic Attributes - Select fields
                      ..._categoryAttributes.entries.map((entry) {
                        final attrName = entry.key;
                        final values = entry.value;
                        final attrType = _attributeTypes[attrName] ?? 1;
                        final isMultiSelect = attrType == 2;
                        final currentValue = _selectedAttributes[attrName];

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                attrName,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (isMultiSelect)
                                // Multi-select
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: values.map((value) {
                                    final selectedValues =
                                        currentValue?.split(',') ?? [];
                                    final isSelected = selectedValues.contains(
                                      value,
                                    );
                                    return FilterChip(
                                      label: Text(value),
                                      selected: isSelected,
                                      onSelected: (selected) {
                                        setState(() {
                                          final current = selectedValues
                                              .toList();
                                          if (selected) {
                                            if (!current.contains(value)) {
                                              current.add(value);
                                            }
                                          } else {
                                            current.remove(value);
                                          }
                                          _selectedAttributes[attrName] =
                                              current.isEmpty
                                              ? null
                                              : current.join(',');
                                        });
                                      },
                                    );
                                  }).toList(),
                                )
                              else
                                // Single select
                                DropdownButtonFormField<String>(
                                  value: currentValue,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  items: values.map((value) {
                                    return DropdownMenuItem(
                                      value: value,
                                      child: Text(value),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedAttributes[attrName] = value;
                                    });
                                  },
                                ),
                            ],
                          ),
                        );
                      }),
                      // Dynamic Attributes - Text fields
                      ..._attributeTypes.entries.where((e) => e.value == 3).map(
                        (entry) {
                          final attrName = entry.key;
                          if (!_textFieldControllers.containsKey(attrName)) {
                            _textFieldControllers[attrName] =
                                TextEditingController(
                                  text: _selectedAttributes[attrName] ?? '',
                                );
                          }
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: TextFormField(
                              controller: _textFieldControllers[attrName],
                              decoration: InputDecoration(
                                labelText: attrName,
                                border: const OutlineInputBorder(),
                              ),
                              onChanged: (value) {
                                _selectedAttributes[attrName] = value;
                              },
                            ),
                          );
                        },
                      ),
                      // Dynamic Attributes - Date fields
                      ..._attributeTypes.entries.where((e) => e.value == 4).map((
                        entry,
                      ) {
                        final attrName = entry.key;
                        final dateStr = _selectedAttributes[attrName];
                        DateTime? dateValue;
                        if (dateStr != null && dateStr.isNotEmpty) {
                          try {
                            dateValue = DateTime.parse(dateStr);
                          } catch (e) {
                            debugPrint('Error parsing date: $e');
                          }
                        }
                        final displayText = dateValue != null
                            ? '${dateValue.day}/${dateValue.month}/${dateValue.year}'
                            : '';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: TextFormField(
                            readOnly: true,
                            controller: TextEditingController(
                              text: displayText,
                            ),
                            decoration: InputDecoration(
                              labelText: attrName,
                              border: const OutlineInputBorder(),
                              suffixIcon: dateValue != null
                                  ? IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        setState(() {
                                          _selectedAttributes[attrName] = null;
                                        });
                                      },
                                    )
                                  : const Icon(Icons.calendar_today),
                            ),
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: dateValue ?? DateTime.now(),
                                firstDate: DateTime(DateTime.now().year - 10),
                                lastDate: DateTime(DateTime.now().year + 10),
                              );
                              if (picked != null) {
                                setState(() {
                                  _selectedAttributes[attrName] = picked
                                      .toIso8601String();
                                });
                              }
                            },
                          ),
                        );
                      }),
                      // Quantity
                      TextFormField(
                        controller: _quantityController,
                        decoration: const InputDecoration(
                          labelText: 'Quantity *',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (value) => value?.isEmpty ?? true
                            ? 'Quantity is required'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      // Price and Sell Price
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _priceController,
                              decoration: const InputDecoration(
                                labelText: 'Price *',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              validator: (value) => value?.isEmpty ?? true
                                  ? 'Price is required'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _sellPriceController,
                              decoration: const InputDecoration(
                                labelText: 'Sell Price *',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              validator: (value) => value?.isEmpty ?? true
                                  ? 'Sell Price is required'
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // HSN and Tax
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _hsnController,
                              decoration: const InputDecoration(
                                labelText: 'HSN Code',
                                border: OutlineInputBorder(),
                              ),
                              maxLength: 8,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _taxPercController,
                              decoration: const InputDecoration(
                                labelText: 'Tax %',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      if (_showHsnWarning)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Warning: HSN does not match selected category',
                            style: TextStyle(
                              color: Colors.red[700],
                              fontSize: 12,
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      // Unit
                      TextFormField(
                        controller: _unitController,
                        decoration: const InputDecoration(
                          labelText: 'Unit',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Description
                      TextFormField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 24),
                      // Actions
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _isSaving
                                  ? null
                                  : () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _isSaving ? null : _saveItem,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                              ),
                              child: _isSaving
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                      ),
                                    )
                                  : const Text('Save'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
