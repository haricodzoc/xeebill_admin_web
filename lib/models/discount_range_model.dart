class DiscountRangeModel {
  int? id;
  double amountFrom;
  double discountPercentage;

  DiscountRangeModel({
    this.id,
    required this.amountFrom,
    required this.discountPercentage,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount_from': amountFrom,
      'discount_percentage': discountPercentage,
    };
  }

  factory DiscountRangeModel.fromMap(Map<String, dynamic> map) {
    return DiscountRangeModel(
      id: map['id'],
      amountFrom: map['amount_from'],
      discountPercentage: map['discount_percentage'],
    );
  }
}
