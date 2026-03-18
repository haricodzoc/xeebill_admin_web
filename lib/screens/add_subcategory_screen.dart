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
  String selectedUnit = 'Piece';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    attributes = {};
    attributeTypes = {};
    if (widget.isUpdate && widget.selectedSubcategory != null) {
      _loadDefaultValues(widget.selectedSubcategory!);
    } else {
      _codeController.text = _generateUniqueCode();
    }
  }

  void _loadDefaultValues(SubCategory subCategory) {
    _codeController.text = subCategory.code;
    _nameController.text = subCategory.name;
    _hsnController.text = subCategory.hsnCode ?? '';
    _gstController.text = subCategory.gstRate?.toString() ?? '';
    selectedUnit = subCategory.unit ?? 'Piece';

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
    // Extract numeric suffixes from existing subcategory codes
    // that match the category code prefix
    List<int> numericSuffixes = [];
    
    for (var subcat in widget.subcategories) {
      // Check if the subcategory code starts with the category code
      if (subcat.code.startsWith('${widget.categoryCode}-')) {
        // Extract the part after the category code and hyphen
        final suffix = subcat.code.substring('${widget.categoryCode}-'.length);
        // Try to parse as integer
        final numericValue = int.tryParse(suffix);
        if (numericValue != null) {
          numericSuffixes.add(numericValue);
        }
      }
    }
    
    // Find the maximum numeric suffix, or start from 1 if none exist
    int nextNumber = 1;
    if (numericSuffixes.isNotEmpty) {
      nextNumber = numericSuffixes.reduce((a, b) => a > b ? a : b) + 1;
    }
    
    // Format as 2-digit zero-padded string
    return '${widget.categoryCode}-${nextNumber.toString().padLeft(2, '0')}';
  }

  String _capitalizeWords(String text) {
    if (text.isEmpty) return text;
    return text
        .split(' ')
        .map((word) {
          if (word.isEmpty) return word;
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }

  List<String> _smartSort(List<String> list) {
    return List<String>.from(list)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  Future<void> _updateFirestoreSubcategories(
    List<SubCategory> updatedSubcategories,
  ) async {
    const int maxRetries = 3;
    int retryCount = 0;

    while (retryCount < maxRetries) {
      try {
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          QuerySnapshot querySnapshot = await FirebaseFirestore.instance
              .collection('general_categories')
              .where('code', isEqualTo: widget.categoryCode)
              .get();

          if (querySnapshot.docs.isEmpty) {
            throw Exception('Category not found in Firestore');
          }

          DocumentReference docRef = querySnapshot.docs.first.reference;
          DocumentSnapshot currentDoc = await transaction.get(docRef);

          if (!currentDoc.exists) {
            throw Exception('Document was deleted during the operation');
          }

          List<dynamic> firestoreSubcategories = [];
          try {
            final raw = currentDoc.get('subcategories');
            if (raw is String) {
              firestoreSubcategories = jsonDecode(raw);
            } else if (raw is List) {
              firestoreSubcategories = raw;
            }
          } catch (e) {
            debugPrint('Error parsing Firestore subcategories: $e');
          }

          List<SubCategory> mergedSubcategories = [];
          for (var subcat in firestoreSubcategories) {
            try {
              mergedSubcategories.add(SubCategory.fromJson(subcat));
            } catch (e) {
              debugPrint('Error converting subcategory: $e');
            }
          }

          for (var updated in updatedSubcategories) {
            int idx = mergedSubcategories.indexWhere(
              (s) => s.code == updated.code,
            );
            if (idx != -1) {
              mergedSubcategories[idx] = updated;
            } else {
              mergedSubcategories.add(updated);
            }
          }

          final seenCodes = <String>{};
          mergedSubcategories = mergedSubcategories.where((s) {
            if (seenCodes.contains(s.code)) return false;
            seenCodes.add(s.code);
            return true;
          }).toList();

          List<Map<String, dynamic>> subcategoriesJson = mergedSubcategories
              .map((subcategory) {
                String attributesToUse = subcategory.attributes;
                if (subcategory.attributes.isNotEmpty) {
                  try {
                    Map<String, dynamic> attributesMap = jsonDecode(
                      subcategory.attributes,
                    );
                    Map<String, dynamic> sortedAttributesMap = {};
                    attributesMap.forEach((key, value) {
                      if (value is Map) {
                        List<String> keys = (value as Map<String, dynamic>).keys
                            .toList();
                        List<String> sortedKeys = _smartSort(keys);
                        Map<String, dynamic> sortedValue = {};
                        for (String k in sortedKeys) {
                          sortedValue[k] = value[k];
                        }
                        sortedAttributesMap[key] = sortedValue;
                      } else {
                        sortedAttributesMap[key] = value;
                      }
                    });
                    attributesToUse = jsonEncode(sortedAttributesMap);
                  } catch (e) {
                    attributesToUse = subcategory.attributes;
                  }
                }
                return {
                  'code': subcategory.code,
                  'name': subcategory.name,
                  'attributes': attributesToUse,
                  'attribute_types': subcategory.attributeTypes,
                  'hsn_code': subcategory.hsnCode,
                  'unit': subcategory.unit ?? 'Piece',
                  'description': subcategory.description ?? '',
                  'gst_rate': subcategory.gstRate,
                };
              })
              .toList();

          transaction.update(docRef, {
            'subcategories': jsonEncode(subcategoriesJson),
            'updated_at': DateTime.now(),
            'version': FieldValue.increment(1),
          });
        });

        debugPrint('Successfully updated subcategories in Firestore');
        return;
      } catch (e) {
        retryCount++;
        debugPrint(
          'Error updating Firestore subcategories (attempt $retryCount): $e',
        );

        if (retryCount >= maxRetries) {
          if (e.toString().contains('already exists')) {
            throw Exception(
              'This subcategory has already been added by another user. Please refresh and try again.',
            );
          } else if (e.toString().contains('not found') ||
              e.toString().contains('deleted')) {
            throw Exception(
              'The category was modified or deleted by another user. Please refresh and try again.',
            );
          } else {
            throw Exception(
              'Failed to save after multiple attempts. Please check your connection and try again.',
            );
          }
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
                    'Note: This will replace all existing attributes.',
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
                    if (value is Map<String, dynamic>) {
                      importedAttributes[key] = <String, bool>{};
                      value.forEach((subKey, subValue) {
                        bool boolValue = false;
                        if (subValue is bool) {
                          boolValue = subValue;
                        } else if (subValue is String) {
                          boolValue = subValue.toLowerCase() == 'true';
                        } else if (subValue is int) {
                          boolValue = subValue != 0;
                        }
                        importedAttributes[key]![subKey] = boolValue;
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
    if (widget.isUpdate == true) {
      if (widget.selectedSubcategory != null &&
          widget.selectedSubcategory!.attributes.isNotEmpty) {
        try {
          String cleanJson = widget.selectedSubcategory!.attributes.replaceAll(
            '\\"',
            '"',
          );
          Map<String, dynamic> originalAttributes = json.decode(cleanJson);
          if (originalAttributes.containsKey(attributeKey)) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Sorry, attribute removal is not permitted after it has been saved once.',
                ),
              ),
            );
            return;
          }
        } catch (e) {
          debugPrint('Error parsing original attributes: $e');
        }
      }
    }
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Remove Attribute',
            style: TextStyle(
              color: AppColors.primaryRed,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Are you sure you want to remove "$attributeKey" and all its items?',
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
    if (widget.isUpdate == true) {
      if (widget.selectedSubcategory != null &&
          widget.selectedSubcategory!.attributes.isNotEmpty) {
        try {
          String cleanJson = widget.selectedSubcategory!.attributes.replaceAll(
            '\\"',
            '"',
          );
          Map<String, dynamic> originalAttributes = json.decode(cleanJson);
          if (originalAttributes.containsKey(attributeKey)) {
            Map<String, dynamic> originalItems =
                originalAttributes[attributeKey];
            if (originalItems.containsKey(itemKey)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Sorry, item removal is not permitted after it has been saved once.',
                  ),
                ),
              );
              return;
            }
          }
        } catch (e) {
          debugPrint('Error parsing original attributes: $e');
        }
      }
    }
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Remove Item',
            style: TextStyle(
              color: AppColors.primaryRed,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Are you sure you want to remove "$itemKey" from $attributeKey?',
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
                              mainAxisExtent: 40,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 4,
                            ),
                        itemCount: attributeEntry.value.entries.length + 1,
                        itemBuilder: (context, index) {
                          if (index == attributeEntry.value.entries.length) {
                            return SizedBox(
                              height: 40,
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
                          return SizedBox(
                            height: 40,
                            child: GestureDetector(
                              onLongPress: () => _showRemoveItemDialog(
                                attributeEntry.key,
                                subEntry.key,
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.primaryGrey.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: AppColors.primaryGrey.withOpacity(
                                      0.3,
                                    ),
                                    width: 1,
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.label_outline,
                                        size: 12,
                                        color: AppColors.primaryGrey,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          subEntry.key,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.primaryGrey,
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
                      items: UNITS
                          .map(
                            (unit) => DropdownMenuItem<String>(
                              value: unit['name'] as String,
                              child: Text(unit['name'] as String),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            selectedUnit = value;
                          });
                        }
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
                          value == null ? 'Please select a unit' : null,
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
                                  (sub) => sub.code == selSubCode,
                                );
                                if (index != -1) {
                                  updatedSubcategories[index] = newCategory;
                                } else {
                                  updatedSubcategories.add(newCategory);
                                }
                              } else {
                                updatedSubcategories.add(newCategory);
                              }

                              await _updateFirestoreSubcategories(
                                updatedSubcategories,
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
