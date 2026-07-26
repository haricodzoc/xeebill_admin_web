import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xeebill_web/models/subcategory_model.dart';
import 'package:xeebill_web/utils/app_colors.dart';
import 'package:xeebill_web/utils/constants.dart';

class AddSubcategoryScreen extends StatefulWidget {
  final String categoryCode;
  final String categoryName;
  final List<SubCategory> subcategories;
  final SubCategory? selectedSubcategory;
  final bool isUpdate;

  const AddSubcategoryScreen({
    super.key,
    required this.categoryCode,
    required this.categoryName,
    required this.subcategories,
    this.selectedSubcategory,
    this.isUpdate = false,
  });

  @override
  State<AddSubcategoryScreen> createState() => _AddSubcategoryScreenState();
}

class _AddSubcategoryScreenState extends State<AddSubcategoryScreen> {
  late Map<String, Map<String, bool>> attributes;
  late Map<String, Map<String, bool>> attributeTypes;
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _hsnController = TextEditingController();
  final TextEditingController _gstController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  /// Must match a [UNITS] `name`, or null when unknown / not yet chosen (avoids DropdownButton assert).
  String? selectedUnit;
  bool _isLoading = false;

  List<String> get _unitDisplayNames {
    return UNITS
        .map((unit) => (unit['name'] as String?)?.trim() ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
  }

  /// Default for new subcategories: Piece if listed, else first unit, else null.
  String? _defaultUnitForNew() {
    final names = _unitDisplayNames;
    if (names.contains('Piece')) return 'Piece';
    if (names.isNotEmpty) return names.first;
    return null;
  }

  @override
  void initState() {
    super.initState();
    attributes = {};
    attributeTypes = {};
    if (widget.isUpdate && widget.selectedSubcategory != null) {
      _loadDefaultValues(widget.selectedSubcategory!);
    } else {
      _codeController.text = _generateUniqueCode();
      selectedUnit = _defaultUnitForNew();
    }
  }

  void _loadDefaultValues(SubCategory subCategory) {
    _codeController.text = subCategory.code;
    _nameController.text = subCategory.name;
    _hsnController.text = subCategory.hsnCode ?? '';
    _gstController.text = subCategory.gstRate?.toString() ?? '';
    final u = subCategory.unit?.trim();
    if (u != null && u.isNotEmpty && _unitDisplayNames.contains(u)) {
      selectedUnit = u;
    } else {
      selectedUnit = null;
    }

    attributes = {};
    try {
      if (subCategory.attributes.isNotEmpty) {
        String cleanJson = subCategory.attributes.replaceAll('\\"', '"');
        Map<String, dynamic> attributesData = json.decode(cleanJson);

        attributesData.forEach((parentKey, parentValue) {
          if (parentValue is Map<String, dynamic>) {
            attributes[parentKey] = <String, bool>{};
            parentValue.forEach((leafKey, leafValue) {
              bool boolValue = false;
              if (leafValue is bool) {
                boolValue = leafValue;
              } else if (leafValue is String) {
                boolValue = leafValue.toLowerCase() == 'true';
              }
              attributes[parentKey]![leafKey] = boolValue;
            });
          }
        });
      }
    } catch (e) {
      debugPrint('Error parsing attributes JSON: $e');
      attributes = {};
    }
  }

  String _generateUniqueCode() {
    final prefix = '${widget.categoryCode}-';
    final usedCodes = {
      for (final s in widget.subcategories) s.code.trim(),
    };

    var maxSuffix = 0;
    for (final subcat in widget.subcategories) {
      final c = subcat.code.trim();
      if (c.startsWith(prefix)) {
        final suffix = c.substring(prefix.length);
        final n = int.tryParse(suffix);
        if (n != null && n > maxSuffix) maxSuffix = n;
      }
    }

    var next = maxSuffix + 1;
    while (true) {
      final candidate =
          '$prefix${next.toString().padLeft(2, '0')}';
      if (!usedCodes.contains(candidate)) return candidate;
      next++;
    }
  }

  /// Subcategory identity is [code]. Duplicates cause Firestore merge to overwrite another row.
  void _assertUniqueSubcategoryCodes(List<SubCategory> list) {
    final seen = <String>{};
    for (final s in list) {
      final c = s.code.trim();
      if (c.isEmpty) {
        throw Exception(
          'Subcategory "${s.name}" has an empty code. Each subcategory must have a unique non-empty code.',
        );
      }
      if (seen.contains(c)) {
        throw Exception(
          'Duplicate subcategory code "$c". Another entry already uses this code — '
          'saving would replace the wrong subcategory (e.g. "Ghee cake" becoming "Cake"). '
          'Use a different code.',
        );
      }
      seen.add(c);
    }
  }

  String _capitalizeWords(String text) {
    if (text.isEmpty) return text;
    return text
        .trim()
        .split(RegExp(r'\s+'))
        .map((word) {
          if (word.isEmpty) return word;
          final hasLetters = RegExp(r'[A-Za-z]').hasMatch(word);
          final isAllCaps = hasLetters && word.toUpperCase() == word;
          if (isAllCaps) return word; // preserve acronyms like "LED"
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }

  List<String> _smartSort(List<String> list) {
    return List<String>.from(list)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  String _sortedAttributesJson(String attributesJson) {
    if (attributesJson.isEmpty) return attributesJson;
    try {
      final attributesMap =
          jsonDecode(attributesJson) as Map<String, dynamic>;
      final sortedAttributesMap = <String, dynamic>{};
      attributesMap.forEach((key, value) {
        if (value is Map) {
          final keys = (value as Map<String, dynamic>).keys.toList();
          final sortedKeys = _smartSort(keys);
          final sortedValue = <String, dynamic>{};
          for (final k in sortedKeys) {
            sortedValue[k] = value[k];
          }
          sortedAttributesMap[key] = sortedValue;
        } else {
          sortedAttributesMap[key] = value;
        }
      });
      return jsonEncode(sortedAttributesMap);
    } catch (_) {
      return attributesJson;
    }
  }

  /// Saves one subcategory into `general_sub_categories`
  /// (document id = code, gen_cat_code = parent general category code).
  Future<void> _saveSubcategoryToCollection(
    SubCategory subcategory, {
    String? previousCode,
  }) async {
    const int maxRetries = 3;
    int retryCount = 0;

    while (retryCount < maxRetries) {
      try {
        final now = DateTime.now().toIso8601String();
        final col =
            FirebaseFirestore.instance.collection('general_sub_categories');
        final code = subcategory.code.trim();
        if (code.isEmpty) {
          throw Exception('Subcategory code cannot be empty');
        }

        final payload = SubCategory(
          name: subcategory.name,
          code: code,
          attributes: _sortedAttributesJson(subcategory.attributes),
          attributeTypes: subcategory.attributeTypes,
          hsnCode: subcategory.hsnCode,
          unit: subcategory.unit ?? 'Piece',
          description: subcategory.description ?? '',
          gstRate: subcategory.gstRate,
        );

        final oldCode = (previousCode ?? '').trim();
        if (oldCode.isNotEmpty && oldCode != code) {
          final oldRef = col.doc(oldCode);
          final oldSnap = await oldRef.get();
          var createdAt = now;
          var remarks = <String, dynamic>{};
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

          final conflict = await col.doc(code).get();
          if (conflict.exists) {
            throw Exception(
              'Subcategory code "$code" already exists. Use a different code.',
            );
          }

          await col.doc(code).set(
                payload.toFirestoreMap(
                  genCatCode: widget.categoryCode,
                  createdAt: createdAt,
                  updatedAt: now,
                  remarks: remarks,
                ),
              );
        } else {
          final ref = col.doc(code);
          final existing = await ref.get();
          if (!widget.isUpdate && existing.exists) {
            throw Exception(
              'Subcategory code "$code" already exists. Use a different code.',
            );
          }

          var createdAt = now;
          var remarks = <String, dynamic>{};
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
            payload.toFirestoreMap(
              genCatCode: widget.categoryCode,
              createdAt: createdAt,
              updatedAt: now,
              remarks: remarks,
            ),
          );
        }

        debugPrint('Successfully saved subcategory to general_sub_categories');
        return;
      } catch (e) {
        retryCount++;
        debugPrint(
          'Error saving subcategory (attempt $retryCount): $e',
        );

        if (retryCount >= maxRetries) {
          if (e.toString().contains('already exists')) {
            rethrow;
          }
          throw Exception(
            'Failed to save after multiple attempts. Please check your connection and try again.',
          );
        }

        await Future.delayed(Duration(milliseconds: 500 * retryCount));
      }
    }
  }

  void _showImportJsonModal() {
    final jsonController = TextEditingController();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Import Attributes from JSON',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryText,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Paste your JSON attributes here:',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.primaryGrey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: jsonController,
                    decoration: InputDecoration(
                      labelText: 'JSON',
                      border: const OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: AppColors.primaryGreen),
                      ),
                      hintText:
                          '{"Brand":{"D-Link":false,"Generic":true},"Type":{"ADSL":false}}',
                    ),
                    maxLines: 10,
                    autofocus: true,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Note: This will replace all existing attributes. '
                    'All imported options start unchecked (false), even if the JSON had true.',
                    style: TextStyle(fontSize: 11, color: Colors.orange[700]),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(color: AppColors.primaryGrey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                final jsonText = jsonController.text.trim();
                if (jsonText.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter JSON data'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                try {
                  // Parse the JSON
                  String cleanJson = jsonText;
                  // Handle escaped quotes if present
                  if (cleanJson.contains('\\"')) {
                    cleanJson = cleanJson.replaceAll('\\"', '"');
                  }

                  final Map<String, dynamic> jsonData = json.decode(cleanJson);

                  // Convert to attributes map structure
                  final Map<String, Map<String, bool>> importedAttributes = {};
                  jsonData.forEach((key, value) {
                    if (value is Map) {
                      importedAttributes[key] = <String, bool>{};
                      value.forEach((subKey, _) {
                        importedAttributes[key]![subKey.toString()] = false;
                      });
                    }
                  });

                  setState(() {
                    attributes = importedAttributes;
                  });

                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Successfully imported ${importedAttributes.length} attribute(s)',
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Invalid JSON: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Import'),
            ),
          ],
        );
      },
    );
  }

  void _showAddAttributeModal() {
    _textController.clear();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Add New Attribute',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryText,
            ),
          ),
          content: TextField(
            controller: _textController,
            decoration: InputDecoration(
              labelText: 'Attribute Name',
              border: const OutlineInputBorder(),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.primaryGreen),
              ),
            ),
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\"'))],
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(color: AppColors.primaryGrey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                if (_textController.text.trim().isNotEmpty) {
                  FocusScope.of(context).unfocus();
                  setState(() {
                    attributes[_capitalizeWords(_textController.text.trim())] =
                        <String, bool>{};
                  });
                  Navigator.of(context).pop();
                  FocusScope.of(context).unfocus();
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

  void _showAddItemModal(String attributeKey) {
    _textController.clear();
    FocusScope.of(context).unfocus();
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Add New value to $attributeKey',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryText,
            ),
          ),
          content: TextField(
            controller: _textController,
            decoration: InputDecoration(
              labelText: 'Attribute Value',
              border: const OutlineInputBorder(),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.primaryGreen),
              ),
            ),
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\"'))],
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(color: AppColors.primaryGrey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                if (_textController.text.trim().isNotEmpty) {
                  FocusScope.of(context).unfocus();
                  setState(() {
                    attributes[attributeKey]![_capitalizeWords(
                          _textController.text.trim(),
                        )] =
                        false;
                  });
                  Navigator.of(context).pop();
                  FocusScope.of(context).unfocus();
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

  void _showRemoveAttributeDialog(String attributeKey) {
    var attributeWasSaved = false;
    if (widget.isUpdate &&
        widget.selectedSubcategory != null &&
        widget.selectedSubcategory!.attributes.isNotEmpty) {
      try {
        final cleanJson = widget.selectedSubcategory!.attributes.replaceAll(
          '\\"',
          '"',
        );
        final originalAttributes =
            json.decode(cleanJson) as Map<String, dynamic>;
        attributeWasSaved = originalAttributes.containsKey(attributeKey);
      } catch (e) {
        debugPrint('Error parsing original attributes: $e');
      }
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Remove attribute?',
            style: TextStyle(
              color: AppColors.primaryRed,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            attributeWasSaved
                ? 'The attribute "$attributeKey" was already saved. Removing it '
                    'and all its values may affect existing items or bills that use '
                    'these options.\n\nAre you sure you want to remove it?'
                : 'Remove "$attributeKey" and all its values? This cannot be undone '
                    'after you save the subcategory.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  attributes.remove(attributeKey);
                });
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryRed,
                foregroundColor: Colors.white,
              ),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );
  }

  void _showRemoveItemDialog(String attributeKey, String itemKey) {
    var itemWasSaved = false;
    if (widget.isUpdate &&
        widget.selectedSubcategory != null &&
        widget.selectedSubcategory!.attributes.isNotEmpty) {
      try {
        final cleanJson = widget.selectedSubcategory!.attributes.replaceAll(
          '\\"',
          '"',
        );
        final originalAttributes =
            json.decode(cleanJson) as Map<String, dynamic>;
        if (originalAttributes.containsKey(attributeKey)) {
          final raw = originalAttributes[attributeKey];
          if (raw is Map) {
            itemWasSaved = raw.containsKey(itemKey);
          }
        }
      } catch (e) {
        debugPrint('Error parsing original attributes: $e');
      }
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Remove value?',
            style: TextStyle(
              color: AppColors.primaryRed,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            itemWasSaved
                ? '"$itemKey" under "$attributeKey" was already saved. Removing it '
                    'may affect existing items or bills that use this option.\n\n'
                    'Remove it anyway?'
                : 'Remove "$itemKey" from "$attributeKey"?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  attributes[attributeKey]!.remove(itemKey);
                });
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryRed,
                foregroundColor: Colors.white,
              ),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _buildCheckboxList() {
    List<Widget> attributeWidgets = [];

    if (attributes.isEmpty) {
      attributeWidgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'No Attributes',
            style: TextStyle(fontSize: 13, color: AppColors.primaryGrey),
          ),
        ),
      );
    } else {
      attributeWidgets.addAll(
        attributes.entries.map((attributeEntry) {
          if (attributeEntry.value.isEmpty) {
            return GestureDetector(
              onLongPress: () => _showRemoveAttributeDialog(attributeEntry.key),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      size: 18,
                      color: AppColors.primaryGrey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        attributeEntry.key,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.primaryGreen,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppColors.primaryGreen.withOpacity(0.5),
                          width: 1,
                        ),
                      ),
                      child: InkWell(
                        onTap: () => _showAddItemModal(attributeEntry.key),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.add,
                                size: 14,
                                color: AppColors.primaryGreen,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Add Item',
                                style: TextStyle(
                                  color: AppColors.primaryGreen,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
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
          } else {
            return GestureDetector(
              onLongPress: () => _showRemoveAttributeDialog(attributeEntry.key),
              child: Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  initiallyExpanded: true,
                  leading: Icon(
                    Icons.folder,
                    size: 18,
                    color: AppColors.primaryGreen,
                  ),
                  title: Text(
                    attributeEntry.key,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                  childrenPadding: const EdgeInsets.only(
                    left: 32,
                    right: 16,
                    bottom: 8,
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisExtent: 48,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 4,
                            ),
                        itemCount: attributeEntry.value.entries.length + 1,
                        itemBuilder: (context, index) {
                          if (index == attributeEntry.value.entries.length) {
                            return SizedBox(
                              height: 48,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: AppColors.primaryGreen.withOpacity(
                                      0.5,
                                    ),
                                    width: 1,
                                  ),
                                ),
                                child: InkWell(
                                  onTap: () =>
                                      _showAddItemModal(attributeEntry.key),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add,
                                        size: 14,
                                        color: AppColors.primaryGreen,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Add New',
                                        style: TextStyle(
                                          color: AppColors.primaryGreen,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }

                          final subEntry = attributeEntry.value.entries
                              .elementAt(index);
                          final attrKey = attributeEntry.key;
                          final valueKey = subEntry.key;
                          final isOn = subEntry.value;
                          return SizedBox(
                            height: 48,
                            child: GestureDetector(
                              onLongPress: () => _showRemoveItemDialog(
                                attrKey,
                                valueKey,
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isOn
                                      ? AppColors.primaryGreen.withOpacity(0.08)
                                      : AppColors.primaryGrey.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isOn
                                        ? AppColors.primaryGreen.withOpacity(
                                            0.45,
                                          )
                                        : AppColors.primaryGrey.withOpacity(
                                            0.3,
                                          ),
                                    width: 1,
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    left: 4,
                                    right: 6,
                                  ),
                                  child: Row(
                                    children: [
                                      Checkbox(
                                        value: isOn,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                        onChanged: (v) {
                                          if (v == null) return;
                                          setState(() {
                                            attributes[attrKey]![valueKey] = v;
                                          });
                                        },
                                      ),
                                      Expanded(
                                        child: Text(
                                          valueKey,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isOn
                                                ? AppColors.primaryGreen
                                                : AppColors.primaryGrey,
                                            fontWeight: isOn
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
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
        }).toList(),
      );
    }

    attributeWidgets.add(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue, width: 2),
                ),
                child: InkWell(
                  onTap: _showImportJsonModal,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.code, size: 18, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(
                          'Import from JSON',
                          style: TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.primaryGreen, width: 2),
                ),
                child: InkWell(
                  onTap: _showAddAttributeModal,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_circle_outline,
                          size: 18,
                          color: AppColors.primaryGreen,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Add New Attribute',
                          style: TextStyle(
                            color: AppColors.primaryGreen,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
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
      ),
    );

    return attributeWidgets;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
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
          widget.categoryName,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryText,
          ),
        ),
        elevation: 0,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                Text(
                  widget.isUpdate
                      ? 'Update subcategory details.'
                      : 'Fill the details to add new subcategory.',
                  style: TextStyle(color: AppColors.secondaryText),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Subcategory Name *',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppColors.primaryGreen),
                    ),
                  ),
                  validator: (value) => value?.isEmpty ?? true
                      ? 'Please enter subcategory name'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _codeController,
                  decoration: InputDecoration(
                    labelText: 'Subcategory Code *',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppColors.primaryGreen),
                    ),
                  ),
                  enabled: !widget.isUpdate,
                  validator: (value) => value?.isEmpty ?? true
                      ? 'Please enter subcategory code'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _hsnController,
                  decoration: InputDecoration(
                    labelText: 'HSN Code',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppColors.primaryGreen),
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.backgroundText,
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 15.0, bottom: 8),
                    child: DropdownButtonFormField<String>(
                      value: selectedUnit,
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('Select unit'),
                        ),
                        ...UNITS.map(
                          (unit) {
                            final name = unit['name'] as String;
                            return DropdownMenuItem<String>(
                              value: name,
                              child: Text(name),
                            );
                          },
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          selectedUnit = value;
                        });
                      },
                      dropdownColor: AppColors.backgroundText,
                      decoration: InputDecoration(
                        labelText: 'Unit',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 5,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      validator: (value) =>
                          value == null || value.isEmpty
                              ? 'Please select a unit'
                              : null,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _gstController,
                  decoration: InputDecoration(
                    labelText: 'Tax Percentage',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppColors.primaryGreen),
                    ),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  maxLength: 2,
                ),
                const SizedBox(height: 26),
                Row(
                  children: [
                    Icon(
                      Icons.list_alt_outlined,
                      size: 18,
                      color: AppColors.primaryGreen,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Attributes',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ..._buildCheckboxList(),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : () async {
                            if (!_formKey.currentState!.validate()) {
                              return;
                            }

                            if (_isLoading) return;

                            setState(() {
                              _isLoading = true;
                            });

                            try {
                              String newCatCode;
                              if (widget.isUpdate &&
                                  widget.selectedSubcategory != null) {
                                newCatCode = widget.selectedSubcategory!.code;
                              } else {
                                newCatCode = _codeController.text.trim();
                              }

                              SubCategory newCategory = SubCategory(
                                code: newCatCode,
                                hsnCode: _hsnController.text.trim().isEmpty
                                    ? null
                                    : _hsnController.text.trim(),
                                unit: selectedUnit,
                                name: _capitalizeWords(
                                  _nameController.text.trim(),
                                ),
                                gstRate: _gstController.text.trim().isEmpty
                                    ? null
                                    : double.tryParse(
                                        _gstController.text.trim(),
                                      ),
                                description: '',
                                attributes: jsonEncode(attributes),
                                attributeTypes: jsonEncode(attributeTypes),
                              );

                              List<SubCategory> updatedSubcategories =
                                  List.from(widget.subcategories);

                              if (widget.isUpdate &&
                                  widget.selectedSubcategory != null) {
                                String selSubCode =
                                    widget.selectedSubcategory!.code;
                                int index = updatedSubcategories.indexWhere(
                                  (sub) =>
                                      sub.code.trim() == selSubCode.trim(),
                                );
                                if (index != -1) {
                                  updatedSubcategories[index] = newCategory;
                                } else {
                                  updatedSubcategories.add(newCategory);
                                }
                              } else {
                                final taken = widget.subcategories
                                    .where(
                                      (s) =>
                                          s.code.trim() ==
                                          newCatCode.trim(),
                                    )
                                    .toList();
                                if (taken.isNotEmpty) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Code "$newCatCode" is already used by '
                                          '"${taken.first.name}". Use a unique code — '
                                          'duplicate codes overwrite the existing subcategory.',
                                        ),
                                        backgroundColor:
                                            AppColors.primaryRed,
                                      ),
                                    );
                                  }
                                  return;
                                }
                                updatedSubcategories.add(newCategory);
                              }

                              _assertUniqueSubcategoryCodes(
                                updatedSubcategories,
                              );

                              await _saveSubcategoryToCollection(
                                newCategory,
                                previousCode: widget.isUpdate
                                    ? widget.selectedSubcategory?.code
                                    : null,
                              );

                              if (mounted) {
                                Navigator.of(context).pop(updatedSubcategories);
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error: $e'),
                                    backgroundColor: AppColors.primaryRed,
                                  ),
                                );
                              }
                            } finally {
                              if (mounted) {
                                setState(() {
                                  _isLoading = false;
                                });
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Text('Save All'),
                  ),
                ),
                const SizedBox(height: 50),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
