// Model for category document
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:xeebill_web/models/subcategory_model.dart';

class GeneralCategory {
  final String id;
  final String code;
  final String categoryName;
  List<SubCategory> subcategories;
  bool isExpanded;
  bool isAllSelected;

  GeneralCategory({
    required this.id,
    required this.code,
    required this.categoryName,
    required this.subcategories,
    this.isExpanded = false,
    this.isAllSelected = false,
  });

  factory GeneralCategory.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    // Parse subcategories from JSON string
    List<SubCategory> subcategories = [];
    if (data['subcategories'] != null) {
      try {
        List<dynamic> subcatData = jsonDecode(data['subcategories']);
        subcategories = subcatData
            .map((item) => SubCategory.fromJson(item))
            .toList();
      } catch (e) {
        debugPrint('Error parsing subcategories: $e');
      }
    }

    return GeneralCategory(
      id: doc.id,
      code: data['code']?.toString() ?? '',
      categoryName: data['category_name']?.toString() ?? 'Unknown Category',
      subcategories: subcategories,
    );
  }
}
