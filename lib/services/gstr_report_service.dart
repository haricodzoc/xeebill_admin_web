import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/bill_item_model.dart';
import '../models/bill_model.dart';
import '../models/sub_profile_model.dart';
import '../models/user_location_model.dart';
import '../utils/constants.dart';
import '../utils/gst_calc.dart';

/// Sentinel for "default / unmapped profiles" location filter (matches bills screen).
const String kDefaultLocationFilterId = '__default_unmapped_profiles__';

class GstrBusinessInfo {
  final String name;
  final String gstNumber;
  final GstType gstType;

  const GstrBusinessInfo({
    required this.name,
    required this.gstNumber,
    required this.gstType,
  });
}

class GstrReportResult {
  final Uint8List bytes;
  final String filename;
  final int invoiceCount;
  final int returnCount;
  final List<String> hsnConflictLines;

  const GstrReportResult({
    required this.bytes,
    required this.filename,
    required this.invoiceCount,
    required this.returnCount,
    this.hsnConflictLines = const [],
  });
}

class InvoiceItemSalesRow {
  final String itemCode;
  final String itemName;
  final String categoryCode;
  final String hsnCode;
  final double taxPerc;
  final double quantitySold;
  final double quantityReturned;

  const InvoiceItemSalesRow({
    required this.itemCode,
    required this.itemName,
    required this.categoryCode,
    required this.hsnCode,
    required this.taxPerc,
    required this.quantitySold,
    required this.quantityReturned,
  });
}

/// Firestore-backed invoice / GSTR report generation (no local DB).
/// Bill line items are read from the `items` JSON field on each bill document.
class GstrReportService {
  GstrReportService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> userRef(String userDocId) =>
      _db.collection('users').doc(userDocId);

  Future<GstrBusinessInfo> loadBusinessInfo(String userDocId) async {
    final snap = await userRef(userDocId).get();
    final data = snap.data() ?? <String, dynamic>{};
    return GstrBusinessInfo(
      name: (data['name'] ?? data['businessName'] ?? '').toString().trim(),
      gstNumber: (data['gstNumber'] ?? data['gst_number'] ?? '').toString().trim(),
      gstType: parseUserGstType(data['gstType'] ?? data['gst_type']),
    );
  }

  Future<List<UserLocationModel>> loadLocations(String userDocId) async {
    final snap = await userRef(userDocId).collection('locations').get();
    final list = <UserLocationModel>[];
    for (final d in snap.docs) {
      try {
        list.add(UserLocationModel.fromFirestore(d));
      } catch (e) {
        debugPrint('Skip location ${d.id}: $e');
      }
    }
    list.sort((a, b) {
      if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  Future<Set<String>?> resolveLocationProfileIds({
    required String userDocId,
    required String? selectedLocationId,
    required List<UserLocationModel> locations,
  }) async {
    if (selectedLocationId == null || selectedLocationId.isEmpty) return null;

    if (selectedLocationId == kDefaultLocationFilterId) {
      final mapped = <String>{};
      for (final loc in locations.where((l) => !l.isDefault)) {
        mapped.addAll(loc.subProfileIds);
      }
      final subSnap = await userRef(userDocId).collection('subProfiles').get();
      final ids = <String>{};
      for (final d in subSnap.docs) {
        final code = (d.data()['code'] ?? '').toString().trim().toUpperCase();
        if (code == 'SA' || code.endsWith('SA')) continue;
        if (!mapped.contains(d.id)) ids.add(d.id);
      }
      return ids;
    }

    for (final loc in locations) {
      if (loc.id == selectedLocationId) {
        return loc.subProfileIds.toSet();
      }
    }
    return <String>{};
  }

  Future<List<BillModel>> fetchBillsInRange({
    required String userDocId,
    required DateTime from,
    required DateTime to,
  }) async {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day, 23, 59, 59, 999);

    final snap = await userRef(userDocId)
        .collection('bills')
        .orderBy('bill_date', descending: true)
        .get();

    final bills = <BillModel>[];
    for (final doc in snap.docs) {
      try {
        final bill = BillModel.fromFirestore(doc);
        final d = DateTime(
          bill.billDate.year,
          bill.billDate.month,
          bill.billDate.day,
        );
        if (d.isBefore(start) || d.isAfter(DateTime(end.year, end.month, end.day))) {
          continue;
        }
        // Ensure items extracted from JSON on the bill doc.
        bill.items ??= [];
        bills.add(bill);
      } catch (e) {
        debugPrint('Skip bill ${doc.id}: $e');
      }
    }
    bills.sort((a, b) => a.billDate.compareTo(b.billDate));
    return bills;
  }

  /// Same order as mobile `PROFILE_CODES`: MP/NMP/RMP, then each sub-profile
  /// (by prefix) plus `N{code}` and `R{code}`.
  Future<List<String>> loadProfileCodeOrder(String userDocId) async {
    final snap = await userRef(userDocId).collection('subProfiles').get();
    final profiles = <SubProfileModel>[];
    for (final d in snap.docs) {
      try {
        profiles.add(SubProfileModel.fromMap(d.data(), d.id));
      } catch (e) {
        debugPrint('Skip subprofile ${d.id}: $e');
      }
    }
    profiles.sort((a, b) {
      final ap = int.tryParse(a.prefix.trim()) ?? 1 << 20;
      final bp = int.tryParse(b.prefix.trim()) ?? 1 << 20;
      final c = ap.compareTo(bp);
      if (c != 0) return c;
      return a.code.toUpperCase().compareTo(b.code.toUpperCase());
    });

    final order = <String>['MP', 'NMP', 'RMP'];
    for (final profile in profiles) {
      final code = profile.code.trim();
      if (code.isEmpty) continue;
      order.add(code);
      order.add('N$code');
      order.add('R$code');
    }
    return order;
  }

  /// Groups invoices by profile code, then bill number — same as mobile GSTR.
  void sortEntriesLikeMobile(
    List<Map<String, dynamic>> entries,
    List<String> profileCodeOrder,
  ) {
    int rank(String code) {
      final i = profileCodeOrder.indexOf(code.trim());
      if (i >= 0) return i;
      final upper = code.trim().toUpperCase();
      final j = profileCodeOrder.indexWhere((c) => c.toUpperCase() == upper);
      return j >= 0 ? j : 100000;
    }

    String groupKey(BillModel bill) {
      final code = bill.profileCode.trim();
      if (code.isNotEmpty && rank(code) < 100000) return code;
      final invoice = bill.invoiceNumber.trim();
      final slash = invoice.indexOf('/');
      if (slash > 0) return invoice.substring(0, slash);
      return code;
    }

    entries.sort((a, b) {
      final ba = a['billInfo'] as BillModel;
      final bb = b['billInfo'] as BillModel;
      final byProfile = rank(groupKey(ba)).compareTo(rank(groupKey(bb)));
      if (byProfile != 0) return byProfile;
      final byNo = ba.billNo.compareTo(bb.billNo);
      if (byNo != 0) return byNo;
      return ba.invoiceNumber.compareTo(bb.invoiceNumber);
    });
  }

  List<Map<String, dynamic>> buildSaleBillEntries({
    required List<BillModel> bills,
    required Set<String>? locationProfileIds,
    required bool regularOnly,
    required bool forGstr,
    GstType accountGstType = GstType.regular,
  }) {
    final out = <Map<String, dynamic>>[];
    for (final bill in bills) {
      final type = gstTypeFromString(bill.type);
      if (type == GstType.saleReturn) continue;
      // Mobile GSTR query uses `completed = 1`, which drops cancelled bills
      // (including negative grand totals) that would skew sheet totals.
      if (forGstr && !bill.completed) continue;
      if (forGstr) {
        if (accountGstType == GstType.regular && type != GstType.regular) {
          continue;
        }
        // Composition report uses non-return sale bills (typically composite).
        if (accountGstType == GstType.composite && type == GstType.unregistered) {
          continue;
        }
      } else if (regularOnly && type == GstType.composite) {
        continue;
      }
      if (locationProfileIds != null &&
          !locationProfileIds.contains(bill.profileId)) {
        continue;
      }
      final items = (bill.items ?? []).where((i) => !i.isReturned).toList();
      if (items.isEmpty && forGstr && accountGstType == GstType.composite) {
        // Composition turnover can still use bill header totals.
      } else if (items.isEmpty) {
        continue;
      }
      out.add({
        'billInfo': bill,
        'items': items,
        'billType': type,
      });
    }
    return out;
  }

  List<Map<String, dynamic>> buildReturnBillEntries({
    required List<BillModel> bills,
    required Set<String>? locationProfileIds,
  }) {
    final out = <Map<String, dynamic>>[];
    for (final bill in bills) {
      if (gstTypeFromString(bill.type) != GstType.saleReturn) continue;
      if (!bill.completed) continue;
      if (locationProfileIds != null &&
          !locationProfileIds.contains(bill.profileId)) {
        continue;
      }
      out.add({
        'billInfo': bill,
        'items': bill.items ?? const <BillItem>[],
      });
    }
    return out;
  }

  List<InvoiceItemSalesRow> aggregateInvoiceItems(
    List<Map<String, dynamic>> saleEntries,
  ) {
    final map = <String, InvoiceItemSalesRow>{};
    for (final entry in saleEntries) {
      final items = entry['items'] as List<BillItem>;
      for (final item in items) {
        final key = item.code;
        final existing = map[key];
        final sold = item.isReturned ? 0.0 : item.quantity;
        final returned = item.isReturned
            ? item.quantity
            : item.returnQuantity;
        if (existing == null) {
          map[key] = InvoiceItemSalesRow(
            itemCode: item.code,
            itemName: item.name,
            categoryCode: item.categoryCode,
            hsnCode: item.hsnCode,
            taxPerc: item.taxPerc,
            quantitySold: sold,
            quantityReturned: returned,
          );
        } else {
          map[key] = InvoiceItemSalesRow(
            itemCode: existing.itemCode,
            itemName: existing.itemName,
            categoryCode: existing.categoryCode,
            hsnCode: existing.hsnCode,
            taxPerc: existing.taxPerc,
            quantitySold: existing.quantitySold + sold,
            quantityReturned: existing.quantityReturned + returned,
          );
        }
      }
    }
    final rows = map.values.toList()
      ..sort((a, b) => a.itemName.toLowerCase().compareTo(b.itemName.toLowerCase()));
    return rows;
  }

  Future<GstrReportResult> generateGstrExcel({
    required GstrBusinessInfo business,
    required DateTime from,
    required DateTime to,
    required List<Map<String, dynamic>> saleEntries,
    required List<Map<String, dynamic>> returnEntries,
    List<String> profileCodeOrder = const [],
  }) async {
    if (profileCodeOrder.isNotEmpty) {
      sortEntriesLikeMobile(saleEntries, profileCodeOrder);
    }
    if (business.gstType == GstType.composite) {
      final bytes = _encodeComposition(
        business: business,
        from: from,
        to: to,
        saleEntries: saleEntries,
      );
      return GstrReportResult(
        bytes: Uint8List.fromList(bytes),
        filename:
            'GSTR_Composition_${DateFormat('yyyyMMdd').format(from)}_${DateFormat('yyyyMMdd').format(to)}.xlsx',
        invoiceCount: saleEntries.length,
        returnCount: returnEntries.length,
      );
    }

    final conflicts = _hsnTaxRateConflicts(saleEntries);
    final bytes = _encodeGstr1(
      business: business,
      from: from,
      to: to,
      saleEntries: saleEntries,
      returnEntries: returnEntries,
    );
    return GstrReportResult(
      bytes: Uint8List.fromList(bytes),
      filename:
          'GSTR1_B2C_${DateFormat('yyyyMMdd').format(from)}_${DateFormat('yyyyMMdd').format(to)}.xlsx',
      invoiceCount: saleEntries.length,
      returnCount: returnEntries.length,
      hsnConflictLines: conflicts.entries.map((e) {
        final rates = e.value
            .map((r) =>
                '${r.toStringAsFixed(r.truncateToDouble() == r ? 0 : 2)}%')
            .join(', ');
        return 'HSN ${e.key}: $rates';
      }).toList(),
    );
  }

  Future<GstrReportResult> generateInvoiceItemsExcel({
    required GstrBusinessInfo business,
    required DateTime from,
    required DateTime to,
    required List<InvoiceItemSalesRow> rows,
    String? locationLabel,
  }) async {
    final excel = Excel.createExcel();
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }
    final sheet = excel['Invoice Item List'];
    var rowIdx = 0;
    void mergeHeader(String text) {
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx),
        CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIdx),
      );
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx))
          .value = TextCellValue(text);
      rowIdx++;
    }

    mergeHeader('Invoice Item List');
    mergeHeader('Business Name: ${business.name}');
    mergeHeader('GSTIN: ${business.gstNumber}');
    mergeHeader(
      'Period: ${DateFormat('dd-MM-yyyy').format(from)} to ${DateFormat('dd-MM-yyyy').format(to)}',
    );
    if (locationLabel != null && locationLabel.trim().isNotEmpty) {
      mergeHeader('Selected Location: $locationLabel');
    }
    rowIdx++;
    sheet.appendRow([
      TextCellValue('Item Code'),
      TextCellValue('Item Name'),
      TextCellValue('Category Code'),
      TextCellValue('HSN'),
      TextCellValue('Tax %'),
      TextCellValue('Sold Quantity'),
      TextCellValue('Returned Quantity'),
    ]);
    for (final r in rows) {
      sheet.appendRow([
        TextCellValue(r.itemCode),
        TextCellValue(r.itemName),
        TextCellValue(r.categoryCode),
        TextCellValue(r.hsnCode),
        DoubleCellValue(r.taxPerc),
        DoubleCellValue(r.quantitySold),
        DoubleCellValue(r.quantityReturned),
      ]);
    }

    final encoded = excel.encode() ?? <int>[];
    return GstrReportResult(
      bytes: Uint8List.fromList(encoded),
      filename:
          'Invoice_Items_${DateFormat('yyyyMMdd').format(from)}_${DateFormat('yyyyMMdd').format(to)}.xlsx',
      invoiceCount: rows.length,
      returnCount: 0,
    );
  }

  Future<GstrReportResult> generateInvoiceListExcel({
    required GstrBusinessInfo business,
    required DateTime from,
    required DateTime to,
    required List<Map<String, dynamic>> saleEntries,
    String? locationLabel,
  }) async {
    final excel = Excel.createExcel();
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }
    final sheet = excel['Invoices'];
    var rowIdx = 0;
    void mergeHeader(String text) {
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx),
        CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIdx),
      );
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx))
          .value = TextCellValue(text);
      rowIdx++;
    }

    mergeHeader('Invoice Report');
    mergeHeader('Business Name: ${business.name}');
    mergeHeader('GSTIN: ${business.gstNumber}');
    mergeHeader(
      'Period: ${DateFormat('dd-MM-yyyy').format(from)} to ${DateFormat('dd-MM-yyyy').format(to)}',
    );
    if (locationLabel != null && locationLabel.trim().isNotEmpty) {
      mergeHeader('Location: $locationLabel');
    }
    rowIdx++;
    sheet.appendRow([
      TextCellValue('Invoice No'),
      TextCellValue('Date'),
      TextCellValue('Customer'),
      TextCellValue('GSTIN'),
      TextCellValue('Type'),
      TextCellValue('Items'),
      TextCellValue('Taxable'),
      TextCellValue('Grand Total'),
    ]);

    for (final entry in saleEntries) {
      final bill = entry['billInfo'] as BillModel;
      final items = entry['items'] as List<BillItem>;
      final gst = calculateBillGstTotals(bill, items);
      sheet.appendRow([
        TextCellValue(bill.invoiceNumber),
        TextCellValue(DateFormat('dd-MM-yyyy').format(bill.billDate)),
        TextCellValue(bill.customerName),
        TextCellValue(bill.customerGst),
        TextCellValue(gstTypeFromString(bill.type).name),
        IntCellValue(items.length),
        TextCellValue((gst['totalTaxable'] ?? 0).toStringAsFixed(2)),
        TextCellValue(bill.grandTotal.toStringAsFixed(2)),
      ]);
    }

    final encoded = excel.encode() ?? <int>[];
    return GstrReportResult(
      bytes: Uint8List.fromList(encoded),
      filename:
          'Invoices_${DateFormat('yyyyMMdd').format(from)}_${DateFormat('yyyyMMdd').format(to)}.xlsx',
      invoiceCount: saleEntries.length,
      returnCount: 0,
    );
  }

  Map<String, Set<double>> _hsnTaxRateConflicts(
    List<Map<String, dynamic>> bills,
  ) {
    final ratesByHsn = <String, Set<double>>{};
    for (final bill in bills) {
      final items = bill['items'] as List<BillItem>;
      for (final item in items) {
        final hsn = item.hsnCode.trim();
        if (hsn.isEmpty) continue;
        ratesByHsn.putIfAbsent(hsn, () => <double>{}).add(item.taxPerc);
      }
    }
    ratesByHsn.removeWhere((_, rates) => rates.length < 2);
    return ratesByHsn;
  }

  List<int> _encodeComposition({
    required GstrBusinessInfo business,
    required DateTime from,
    required DateTime to,
    required List<Map<String, dynamic>> saleEntries,
  }) {
    final excel = Excel.createExcel();
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }
    final sheet = excel['GSTR_CMP_B2C'];
    _writeBusinessHeader(sheet, business, from, to, lastCol: 8);

    String financialYear = '';
    if (saleEntries.isNotEmpty) {
      financialYear =
          (saleEntries.first['billInfo'] as BillModel).financialYear;
    }
    final quarter = _quarterLabel(from);
    double totalTurnover = 0;
    for (final e in saleEntries) {
      totalTurnover += (e['billInfo'] as BillModel).grandTotal;
    }
    final taxRate = GSTR_CMP_TAX_PERC;
    final gstAmount = (totalTurnover * taxRate) / 100;
    final half = gstAmount / 2;

    sheet.appendRow([
      TextCellValue('Financial Year'),
      TextCellValue('Quarter'),
      TextCellValue('Total Turnover'),
      TextCellValue('Taxable Turnover'),
      TextCellValue('Composition Tax Rate (%)'),
      TextCellValue('CGST Amount'),
      TextCellValue('SGST Amount'),
      TextCellValue('GST Amount'),
      TextCellValue('Total Tax Payable'),
    ]);
    sheet.appendRow([
      TextCellValue(financialYear),
      TextCellValue(quarter),
      TextCellValue(totalTurnover.toStringAsFixed(2)),
      TextCellValue(totalTurnover.toStringAsFixed(2)),
      TextCellValue(taxRate.toStringAsFixed(2)),
      TextCellValue(half.toStringAsFixed(2)),
      TextCellValue(half.toStringAsFixed(2)),
      TextCellValue(gstAmount.toStringAsFixed(2)),
      TextCellValue(gstAmount.toStringAsFixed(2)),
    ]);
    return excel.encode() ?? <int>[];
  }

  List<int> _encodeGstr1({
    required GstrBusinessInfo business,
    required DateTime from,
    required DateTime to,
    required List<Map<String, dynamic>> saleEntries,
    required List<Map<String, dynamic>> returnEntries,
  }) {
    final excel = Excel.createExcel();
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    // --- GSTR1_B2C ---
    final b2c = excel['GSTR1_B2C'];
    _writeBusinessHeader(b2c, business, from, to, lastCol: 7);
    b2c.appendRow([
      TextCellValue('Invoice No'),
      TextCellValue('Date'),
      TextCellValue('Party GSTIN'),
      TextCellValue('Invoice Value'),
      TextCellValue('Taxable Value'),
      TextCellValue('CGST'),
      TextCellValue('SGST'),
      TextCellValue('IGST'),
    ]);

    double totalInvoice = 0;
    double totalTaxable = 0;
    double totalCgst = 0;
    double totalSgst = 0;
    double totalIgst = 0;

    for (final entry in saleEntries) {
      final bill = entry['billInfo'] as BillModel;
      final items = entry['items'] as List<BillItem>;
      final gst = calculateBillGstTotals(bill, items);
      final taxable = gst['totalTaxable'] ?? 0;
      final cgst = gst['cgstTotal'] ?? 0;
      final sgst = gst['sgstTotal'] ?? 0;
      final igst = gst['igstTotal'] ?? 0;
      totalInvoice += bill.grandTotal;
      totalTaxable += taxable;
      totalCgst += cgst;
      totalSgst += sgst;
      totalIgst += igst;
      b2c.appendRow([
        TextCellValue(bill.invoiceNumber),
        TextCellValue(DateFormat('dd-MM-yyyy').format(bill.billDate)),
        TextCellValue(bill.customerGst),
        TextCellValue(bill.grandTotal.toStringAsFixed(2)),
        TextCellValue(taxable.toStringAsFixed(2)),
        TextCellValue(cgst.toStringAsFixed(2)),
        TextCellValue(sgst.toStringAsFixed(2)),
        TextCellValue(igst.toStringAsFixed(2)),
      ]);
    }
    b2c.appendRow([
      TextCellValue('TOTAL'),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(totalInvoice.toStringAsFixed(2)),
      TextCellValue(totalTaxable.toStringAsFixed(2)),
      TextCellValue(totalCgst.toStringAsFixed(2)),
      TextCellValue(totalSgst.toStringAsFixed(2)),
      TextCellValue(totalIgst.toStringAsFixed(2)),
    ]);

    // --- GSTR1_B2C_HSN ---
    final hsnSheet = excel['GSTR1_B2C_HSN'];
    _writeBusinessHeader(hsnSheet, business, from, to, lastCol: 11);
    hsnSheet.appendRow([
      TextCellValue('HSN/SAC'),
      TextCellValue('Description'),
      TextCellValue('UQC'),
      TextCellValue('Total Quantity'),
      TextCellValue('Total Value'),
      TextCellValue('Taxable Value'),
      TextCellValue('CGST Rate'),
      TextCellValue('CGST Amount'),
      TextCellValue('SGST Rate'),
      TextCellValue('SGST Amount'),
      TextCellValue('IGST Rate'),
      TextCellValue('IGST Amount'),
    ]);

    final hsnSummary = <String, Map<String, dynamic>>{};
    for (final entry in saleEntries) {
      final bill = entry['billInfo'] as BillModel;
      final items = entry['items'] as List<BillItem>;
      final allocated = allocateBillItemGstLines(
        items: items,
        targetInclusive: bill.grandTotal,
      );
      for (final line in allocated) {
        final item = line.item;
        final taxRate = item.taxPerc;
        final key = '${item.hsnCode.trim()}|${taxRate.toStringAsFixed(6)}';
        final summary = hsnSummary.putIfAbsent(key, () => {
              'hsnCode': item.hsnCode,
              'taxRate': taxRate,
              'description': item.name,
              'uqc': 'NOS',
              'totalQuantity': 0.0,
              'totalValue': 0.0,
              'taxableValue': 0.0,
              'cgstRate': 0.0,
              'cgstAmount': 0.0,
              'sgstRate': 0.0,
              'sgstAmount': 0.0,
              'igstRate': 0.0,
              'igstAmount': 0.0,
            });
        summary['totalQuantity'] =
            (summary['totalQuantity'] as double) + line.quantity;
        summary['totalValue'] =
            (summary['totalValue'] as double) + line.discountedInclusive;
        summary['taxableValue'] =
            (summary['taxableValue'] as double) + line.taxable;
        if (taxRate > 0) {
          summary['cgstRate'] = taxRate / 2;
          summary['sgstRate'] = taxRate / 2;
          summary['cgstAmount'] =
              (summary['cgstAmount'] as double) + line.gst / 2;
          summary['sgstAmount'] =
              (summary['sgstAmount'] as double) + line.gst / 2;
        }
      }
    }

    final sortedHsn = hsnSummary.values.toList()
      ..sort((a, b) {
        final rateCmp =
            (a['taxRate'] as num).toDouble().compareTo((b['taxRate'] as num).toDouble());
        if (rateCmp != 0) return rateCmp;
        return (a['hsnCode'] as String).compareTo(b['hsnCode'] as String);
      });

    double hsnQty = 0, hsnVal = 0, hsnTaxable = 0, hsnCgst = 0, hsnSgst = 0, hsnIgst = 0;
    for (final data in sortedHsn) {
      hsnQty += (data['totalQuantity'] as num).toDouble();
      hsnVal += (data['totalValue'] as num).toDouble();
      hsnTaxable += (data['taxableValue'] as num).toDouble();
      hsnCgst += (data['cgstAmount'] as num).toDouble();
      hsnSgst += (data['sgstAmount'] as num).toDouble();
      hsnIgst += (data['igstAmount'] as num).toDouble();
      hsnSheet.appendRow([
        TextCellValue(data['hsnCode']?.toString() ?? ''),
        TextCellValue(data['description']?.toString() ?? ''),
        TextCellValue(data['uqc']?.toString() ?? 'NOS'),
        DoubleCellValue((data['totalQuantity'] as num).toDouble()),
        TextCellValue((data['totalValue'] as num).toStringAsFixed(2)),
        TextCellValue((data['taxableValue'] as num).toStringAsFixed(2)),
        DoubleCellValue((data['cgstRate'] as num).toDouble()),
        TextCellValue((data['cgstAmount'] as num).toStringAsFixed(2)),
        DoubleCellValue((data['sgstRate'] as num).toDouble()),
        TextCellValue((data['sgstAmount'] as num).toStringAsFixed(2)),
        DoubleCellValue((data['igstRate'] as num).toDouble()),
        TextCellValue((data['igstAmount'] as num).toStringAsFixed(2)),
      ]);
    }
    hsnSheet.appendRow([
      TextCellValue('TOTAL'),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(hsnQty.toStringAsFixed(2)),
      TextCellValue(hsnVal.toStringAsFixed(2)),
      TextCellValue(hsnTaxable.toStringAsFixed(2)),
      TextCellValue(''),
      TextCellValue(hsnCgst.toStringAsFixed(2)),
      TextCellValue(''),
      TextCellValue(hsnSgst.toStringAsFixed(2)),
      TextCellValue(''),
      TextCellValue(hsnIgst.toStringAsFixed(2)),
    ]);

    // --- Credit notes ---
    if (returnEntries.isNotEmpty) {
      final credit = excel['GSTR1_CREDIT_NOTES'];
      _writeBusinessHeader(credit, business, from, to, lastCol: 15);
      credit.appendRow([
        TextCellValue('Credit_Note_No'),
        TextCellValue('Credit_Note_Date'),
        TextCellValue('Original_Invoice_No'),
        TextCellValue('Original_Invoice_Date'),
        TextCellValue('Customer_Name'),
        TextCellValue('Customer_GSTIN'),
        TextCellValue('Customer_State_Code'),
        TextCellValue('Place_Of_Supply'),
        TextCellValue('Supply_Type (B2B/B2C)'),
        TextCellValue('Is_GST_Applicable'),
        TextCellValue('Reason_For_Return'),
        TextCellValue('Remarks'),
        TextCellValue('Note_Value'),
        TextCellValue('Taxable_Value'),
        TextCellValue('GST_Rate'),
        TextCellValue('Net_Amount'),
      ]);

      final included = <Map<String, dynamic>>[];
      for (final entry in returnEntries) {
        final bill = entry['billInfo'] as BillModel;
        final items = entry['items'] as List<BillItem>? ?? const <BillItem>[];
        final addInfo = parseAdditionalInfo(bill.additionalInfo) ?? {};
        final isGstApplicable = addInfo['isReturnWithGst'] == true;
        if (business.gstType == GstType.regular && !isGstApplicable) {
          continue;
        }
        final gstin = bill.customerGst;
        final taxable = items.fold<double>(
          0,
          (acc, item) =>
              acc + ((item.totalAfterTax * 100) / (100 + item.taxPerc)),
        );
        final rates = items.map((e) => e.taxPerc.toStringAsFixed(2)).toSet();
        final gstRate = rates.isEmpty
            ? '0.00'
            : (rates.length == 1 ? rates.first : 'Mixed(${rates.join(',')})');
        credit.appendRow([
          TextCellValue(bill.invoiceNumber),
          TextCellValue(DateFormat('dd-MM-yyyy').format(bill.billDate)),
          TextCellValue((addInfo['originalInvoiceNumber'] ?? '').toString()),
          TextCellValue((addInfo['originalInvoiceDate'] ?? '').toString()),
          TextCellValue(bill.customerName),
          TextCellValue(gstin),
          TextCellValue(gstin.length >= 2 ? gstin.substring(0, 2) : ''),
          TextCellValue(
            business.gstNumber.length >= 2
                ? business.gstNumber.substring(0, 2)
                : '',
          ),
          TextCellValue(gstin.isNotEmpty ? 'B2B' : 'B2C'),
          TextCellValue(isGstApplicable ? 'Yes' : 'No'),
          TextCellValue(
            (addInfo['reasonForReturn'] ?? addInfo['returnReason'] ?? '')
                .toString(),
          ),
          TextCellValue((addInfo['remarks'] ?? '').toString()),
          TextCellValue(bill.grandTotal.toStringAsFixed(2)),
          TextCellValue(taxable.toStringAsFixed(2)),
          TextCellValue(gstRate),
          TextCellValue(
            (bill.netPayable == 0 ? bill.grandTotal : bill.netPayable)
                .toStringAsFixed(2),
          ),
        ]);
        included.add({'billInfo': bill, 'items': items});
      }

      final creditHsn = excel['GSTR1_B2C_CREDIT_NOTE_HSN'];
      _writeBusinessHeader(creditHsn, business, from, to, lastCol: 11);
      creditHsn.appendRow([
        TextCellValue('HSN/SAC'),
        TextCellValue('Description'),
        TextCellValue('UQC'),
        TextCellValue('Total Quantity'),
        TextCellValue('Total Value'),
        TextCellValue('Taxable Value'),
        TextCellValue('CGST Rate'),
        TextCellValue('CGST Amount'),
        TextCellValue('SGST Rate'),
        TextCellValue('SGST Amount'),
        TextCellValue('IGST Rate'),
        TextCellValue('IGST Amount'),
      ]);
      final creditHsnSummary = <String, Map<String, dynamic>>{};
      for (final entry in included) {
        final bill = entry['billInfo'] as BillModel;
        final items = entry['items'] as List<BillItem>;
        final allocated = allocateBillItemGstLines(
          items: items,
          targetInclusive: bill.grandTotal,
        );
        for (final line in allocated) {
          final item = line.item;
          final summary = creditHsnSummary.putIfAbsent(item.hsnCode, () => {
                'description': item.name,
                'uqc': 'NOS',
                'totalQuantity': 0.0,
                'totalValue': 0.0,
                'taxableValue': 0.0,
                'cgstRate': 0.0,
                'cgstAmount': 0.0,
                'sgstRate': 0.0,
                'sgstAmount': 0.0,
                'igstRate': 0.0,
                'igstAmount': 0.0,
              });
          summary['totalQuantity'] =
              (summary['totalQuantity'] as double) + line.quantity;
          summary['totalValue'] =
              (summary['totalValue'] as double) + line.discountedInclusive;
          summary['taxableValue'] =
              (summary['taxableValue'] as double) + line.taxable;
          if (item.taxPerc > 0) {
            summary['cgstRate'] = item.taxPerc / 2;
            summary['sgstRate'] = item.taxPerc / 2;
            summary['cgstAmount'] =
                (summary['cgstAmount'] as double) + line.gst / 2;
            summary['sgstAmount'] =
                (summary['sgstAmount'] as double) + line.gst / 2;
          }
        }
      }
      creditHsnSummary.forEach((hsnCode, data) {
        creditHsn.appendRow([
          TextCellValue(hsnCode),
          TextCellValue(data['description']?.toString() ?? ''),
          TextCellValue(data['uqc']?.toString() ?? 'NOS'),
          DoubleCellValue((data['totalQuantity'] as num).toDouble()),
          TextCellValue((data['totalValue'] as num).toStringAsFixed(2)),
          TextCellValue((data['taxableValue'] as num).toStringAsFixed(2)),
          DoubleCellValue((data['cgstRate'] as num).toDouble()),
          TextCellValue((data['cgstAmount'] as num).toStringAsFixed(2)),
          DoubleCellValue((data['sgstRate'] as num).toDouble()),
          TextCellValue((data['sgstAmount'] as num).toStringAsFixed(2)),
          DoubleCellValue((data['igstRate'] as num).toDouble()),
          TextCellValue((data['igstAmount'] as num).toStringAsFixed(2)),
        ]);
      });
    }

    return excel.encode() ?? <int>[];
  }

  void _writeBusinessHeader(
    Sheet sheet,
    GstrBusinessInfo business,
    DateTime from,
    DateTime to, {
    required int lastCol,
  }) {
    void mergeRow(int row, String text, {bool bold = false, double fontSize = 12}) {
      sheet.merge(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
        CellIndex.indexByColumnRow(columnIndex: lastCol, rowIndex: row),
      );
      final cell =
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
      cell.value = TextCellValue(text);
      cell.cellStyle = CellStyle(
        bold: bold,
        fontSize: fontSize.toInt(),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );
    }

    mergeRow(0, business.name, bold: true, fontSize: 18);
    mergeRow(1, 'GSTIN: ${business.gstNumber}', fontSize: 14);
    mergeRow(
      2,
      'Period: ${DateFormat('dd-MM-yyyy').format(from)} to ${DateFormat('dd-MM-yyyy').format(to)}',
    );
    mergeRow(3, '');
    mergeRow(4, '');
  }

  String _quarterLabel(DateTime date) {
    final month = date.month;
    if (month >= 4 && month <= 6) return 'Q1';
    if (month >= 7 && month <= 9) return 'Q2';
    if (month >= 10 && month <= 12) return 'Q3';
    return 'Q4';
  }
}
