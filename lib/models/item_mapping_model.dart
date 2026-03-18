class ItemMappingModel {
  int? id;
  final int itemId;
  final String mapCode;
  final String itemCode;
  final DateTime createdAt;
  final DateTime updatedAt;

  ItemMappingModel({
    this.id,
    required this.itemId,
    required this.mapCode,
    required this.itemCode,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : this.createdAt = createdAt ?? DateTime.now(),
        this.updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap({bool isRestoring = false}) {
    final map = {
      'id': id,
      'item_id': itemId,
      'map_code': mapCode,
      'item_code': itemCode,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };

    return map;
  }

  factory ItemMappingModel.fromMap(Map<String, dynamic> map) {
    return ItemMappingModel(
      id: map['id'] as int?,
      itemId: map['item_id'] as int,
      mapCode: map['map_code'] as String,
      itemCode: map['item_code'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
