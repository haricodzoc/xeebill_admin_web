import 'dart:convert';

import '../models/bill_item_model.dart';
import '../models/bill_model.dart';
import 'constants.dart';

/// Parses bill `type` strings from Firestore / mobile (`GstType.regular`, `regular`, etc.).
GstType gstTypeFromString(String? raw) {
  final s = (raw ?? '').trim().toLowerCase();
  if (s.isEmpty) return GstType.composite;
  if (s.contains('salereturn') || s.contains('sale_return') || s == 'return') {
    return GstType.saleReturn;
  }
  if (s.contains('unregistered')) return GstType.unregistered;
  if (s.contains('composite') || s.contains('composition')) {
    return GstType.composite;
  }
  if (s.contains('regular')) return GstType.regular;
  return GstType.composite;
}

GstType parseUserGstType(dynamic raw) {
  final s = (raw ?? '').toString().trim().toLowerCase();
  if (s.contains('unregistered')) return GstType.unregistered;
  if (s.contains('composite') || s.contains('composition')) {
    return GstType.composite;
  }
  return GstType.regular;
}

/// Inclusive amount of a bill line that counts toward GST.
/// Skips returned lines and scales by net qty when [BillItem.returnQuantity] > 0.
double billItemGstInclusiveAmount(BillItem item) {
  if (item.isReturned) return 0;
  final qty = item.quantity;
  if (qty <= 0) return 0;
  final netQty = (qty - item.returnQuantity).clamp(0.0, qty);
  if (netQty <= 0) return 0;
  if ((netQty - qty).abs() < 1e-9) return item.totalAfterTax;
  return item.totalAfterTax * (netQty / qty);
}

/// Net quantity that counts toward GST / HSN qty.
double billItemGstQuantity(BillItem item) {
  if (item.isReturned) return 0;
  final qty = item.quantity;
  if (qty <= 0) return 0;
  return (qty - item.returnQuantity).clamp(0.0, qty);
}

class AllocatedBillItemGstLine {
  final BillItem item;
  final double inclusive;
  final double quantity;
  final double itemDiscount;
  final double discountedInclusive;
  final double taxable;
  final double gst;

  const AllocatedBillItemGstLine({
    required this.item,
    required this.inclusive,
    required this.quantity,
    required this.itemDiscount,
    required this.discountedInclusive,
    required this.taxable,
    required this.gst,
  });
}

/// Allocates bill-level reduction across inclusive line amounts, then backs out
/// taxable / GST per line tax %.
///
/// Uses [targetInclusive] (usually [BillModel.grandTotal]) as the amount lines
/// must sum to after discount — same as mobile `allocateBillItemGstLines`.
List<AllocatedBillItemGstLine> allocateBillItemGstLines({
  required List<BillItem> items,
  required double targetInclusive,
}) {
  final lines = <({BillItem item, double inclusive, double quantity})>[];
  for (final item in items) {
    final inclusive = billItemGstInclusiveAmount(item);
    final quantity = billItemGstQuantity(item);
    if (inclusive <= 0 || quantity <= 0) continue;
    lines.add((item: item, inclusive: inclusive, quantity: quantity));
  }

  final totalInclusive =
      lines.fold<double>(0, (acc, line) => acc + line.inclusive);
  final safeTarget = targetInclusive.clamp(0.0, double.infinity);
  final effectiveDiscount =
      totalInclusive > safeTarget ? totalInclusive - safeTarget : 0.0;

  final out = <AllocatedBillItemGstLine>[];
  var allocatedDiscount = 0.0;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final double itemDiscount;
    if (i < lines.length - 1 && totalInclusive > 0) {
      itemDiscount = (line.inclusive / totalInclusive) * effectiveDiscount;
      allocatedDiscount += itemDiscount;
    } else {
      itemDiscount = effectiveDiscount - allocatedDiscount;
    }

    final discountedInclusive =
        (line.inclusive - itemDiscount).clamp(0.0, double.infinity);
    final taxPerc = line.item.taxPerc;
    final taxable = taxPerc > 0
        ? (discountedInclusive * 100) / (100 + taxPerc)
        : discountedInclusive;
    final gst = discountedInclusive - taxable;

    out.add(
      AllocatedBillItemGstLine(
        item: line.item,
        inclusive: line.inclusive,
        quantity: line.quantity,
        itemDiscount: itemDiscount,
        discountedInclusive: discountedInclusive,
        taxable: taxable,
        gst: gst,
      ),
    );
  }

  return out;
}

/// Calculates GST / taxable for a bill.
///
/// Discount is allocated on inclusive line amounts via [allocateBillItemGstLines]
/// (reconciled to [BillModel.grandTotal]), so sheet 1 totals match HSN sheet 2.
Map<String, double> calculateBillGstTotals(
  BillModel billInfo,
  List<BillItem> items,
) {
  final gstType = gstTypeFromString(billInfo.type);
  double gstTotal = 0;
  double cgstTotal = 0;
  double igstTotal = 0;
  double sgstTotal = 0;
  double totalTaxableAfterDiscount = 0;

  if (gstType == GstType.regular) {
    final allocated = allocateBillItemGstLines(
      items: items,
      targetInclusive: billInfo.grandTotal,
    );
    for (final line in allocated) {
      totalTaxableAfterDiscount += line.taxable;
      gstTotal += line.gst;
      cgstTotal += line.gst / 2;
      sgstTotal += line.gst / 2;
    }
  }

  double round2(double v) => double.parse(v.toStringAsFixed(2));
  return {
    'gstTotal': round2(gstTotal),
    'cgstTotal': round2(cgstTotal),
    'sgstTotal': round2(sgstTotal),
    'igstTotal': round2(igstTotal),
    'totalTaxable': round2(totalTaxableAfterDiscount),
  };
}

Map<String, dynamic>? parseAdditionalInfo(dynamic additionalInfo) {
  try {
    if (additionalInfo == null) return null;
    if (additionalInfo is Map<String, dynamic>) return additionalInfo;
    if (additionalInfo is Map) return Map<String, dynamic>.from(additionalInfo);
    if (additionalInfo is String && additionalInfo.trim().isNotEmpty) {
      final decoded = jsonDecode(additionalInfo);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
  } catch (_) {}
  return null;
}
