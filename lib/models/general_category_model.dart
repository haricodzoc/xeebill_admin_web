import 'package:cloud_firestore/cloud_firestore.dart';
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

    return GeneralCategory(
      id: doc.id,
      code: data['code']?.toString() ?? '',
      categoryName: data['category_name']?.toString() ?? 'Unknown Category',
      // Subcategories live in `general_sub_categories` (matched by gen_cat_code).
      subcategories: [],
    );
  }

  /// Loads all docs from `general_sub_categories` and attaches them to categories
  /// where `category.code == gen_cat_code`.
  static Future<void> attachSubcategoriesFromCollection(
    List<GeneralCategory> categories,
  ) async {
    final snap =
        await FirebaseFirestore.instance.collection('general_sub_categories').get();

    final byGenCatCode = <String, List<SubCategory>>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final genCatCode = (data['gen_cat_code'] ?? '').toString().trim();
      if (genCatCode.isEmpty) continue;

      byGenCatCode.putIfAbsent(genCatCode, () => []).add(
            SubCategory.fromFirestoreData(data, documentId: doc.id),
          );
    }

    for (final category in categories) {
      final list = byGenCatCode[category.code.trim()] ?? [];
      list.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      category.subcategories = list;
    }
  }
}
