import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/bill_item_model.dart';
import '../models/bill_model.dart';
import '../utils/app_colors.dart';
import '../utils/constants.dart';

class EditBillScreen extends StatefulWidget {
  final String userDocumentId;
  final String billDocId;
  final BillModel bill;

  const EditBillScreen({
    super.key,
    required this.userDocumentId,
    required this.billDocId,
    required this.bill,
  });

  @override
  State<EditBillScreen> createState() => _EditBillScreenState();
}

class _EditableItem {
  _EditableItem(BillItem item)
      : name = TextEditingController(text: item.name),
        code = TextEditingController(text: item.code),
        hsn = TextEditingController(text: item.hsnCode),
        unit = TextEditingController(text: item.unit),
        categoryCode = TextEditingController(text: item.categoryCode),
        price = TextEditingController(text: _fmt(item.price)),
        quantity = TextEditingController(text: _fmt(item.quantity)),
        taxPerc = TextEditingController(text: _fmt(item.taxPerc)),
        returnQuantity =
            TextEditingController(text: _fmt(item.returnQuantity)),
        id = item.id,
        billId = item.billId,
        isReturned = item.isReturned,
        originalQuantity = item.originalQuantity,
        total = item.total,
        totalAfterTax = item.totalAfterTax;

  final int? id;
  final int billId;
  final double originalQuantity;
  final TextEditingController name;
  final TextEditingController code;
  final TextEditingController hsn;
  final TextEditingController unit;
  final TextEditingController categoryCode;
  final TextEditingController price;
  final TextEditingController quantity;
  final TextEditingController taxPerc;
  final TextEditingController returnQuantity;
  bool isReturned;
  double total;
  double totalAfterTax;

  static String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }

  double parseNum(TextEditingController c) =>
      double.tryParse(c.text.trim()) ?? 0;

  void recalculate({required bool taxInclusive}) {
    final p = parseNum(price);
    final q = parseNum(quantity);
    final tax = parseNum(taxPerc);
    var afterTax = p * q;
    double beforeTax;
    if (!taxInclusive) {
      beforeTax = afterTax;
      if (tax > 0) afterTax += afterTax * tax / 100;
    } else if (tax > 0) {
      beforeTax = (afterTax * 100) / (100 + tax);
    } else {
      beforeTax = afterTax;
    }
    total = beforeTax;
    totalAfterTax = afterTax;
  }

  BillItem toBillItem() {
    return BillItem(
      id: id,
      billId: billId,
      name: name.text.trim(),
      hsnCode: hsn.text.trim(),
      unit: unit.text.trim(),
      categoryCode: categoryCode.text.trim(),
      code: code.text.trim(),
      price: parseNum(price),
      quantity: parseNum(quantity),
      returnQuantity: parseNum(returnQuantity),
      total: total,
      taxPerc: parseNum(taxPerc),
      totalAfterTax: totalAfterTax,
      isReturned: isReturned,
      originalQuantity: originalQuantity,
    );
  }

  void dispose() {
    name.dispose();
    code.dispose();
    hsn.dispose();
    unit.dispose();
    categoryCode.dispose();
    price.dispose();
    quantity.dispose();
    taxPerc.dispose();
    returnQuantity.dispose();
  }
}

class _EditBillScreenState extends State<EditBillScreen> {
  final _invoiceController = TextEditingController();
  final _customerNameController = TextEditingController();
  final _customerGstController = TextEditingController();
  final _customerAddressController = TextEditingController();
  final _customerCodeController = TextEditingController();
  final _creditAmountController = TextEditingController();
  final _discountValueController = TextEditingController();

  late GstType _gstType;
  late PaymentModes _paymentMode;
  late DateTime _billDate;
  late TimeOfDay _billTime;
  late DateTime _dueDate;
  bool _taxInclusive = TAX_RATE_INCLUSIVE;
  bool _discountIsPercentage = false;
  bool _saving = false;

  late List<_EditableItem> _items;

  @override
  void initState() {
    super.initState();
    final bill = widget.bill;
    _invoiceController.text = bill.invoiceNumber;
    _customerNameController.text = bill.customerName;
    _customerGstController.text = bill.customerGst;
    _customerAddressController.text = bill.customerAddress;
    _customerCodeController.text = bill.customerCode;
    _creditAmountController.text = _fmt(bill.creditAmount);
    _gstType = _parseGstType(bill.type);
    _paymentMode = _parsePaymentMode(bill.paymentMode);
    _billDate = bill.billDate;
    _billTime = TimeOfDay.fromDateTime(bill.billTime);
    _dueDate = bill.dueDate;
    _items = (bill.items ?? []).map(_EditableItem.new).toList();

    if (bill.discount > 0) {
      _discountIsPercentage = false;
      _discountValueController.text = _fmt(bill.discount);
    }

    _recalculateAll();
  }

  @override
  void dispose() {
    _invoiceController.dispose();
    _customerNameController.dispose();
    _customerGstController.dispose();
    _customerAddressController.dispose();
    _customerCodeController.dispose();
    _creditAmountController.dispose();
    _discountValueController.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }

  GstType _parseGstType(String raw) {
    final v = raw.toLowerCase();
    if (v.contains('regular')) return GstType.regular;
    if (v.contains('unregistered')) return GstType.unregistered;
    if (v.contains('salereturn') || v.contains('sale_return') || v.contains('sale return')) {
      return GstType.saleReturn;
    }
    return GstType.composite;
  }

  PaymentModes _parsePaymentMode(String raw) {
    final v = raw.toLowerCase();
    if (v.contains('multi')) return PaymentModes.multiPay;
    if (v.contains('credit')) return PaymentModes.credit;
    if (v.contains('card')) return PaymentModes.card;
    if (v.contains('upi')) return PaymentModes.upi;
    if (v.contains('wallet')) return PaymentModes.wallet;
    if (v.contains('cheque')) return PaymentModes.cheque;
    return PaymentModes.cash;
  }

  void _recalculateAll() {
    for (final item in _items) {
      item.recalculate(taxInclusive: _taxInclusive);
    }
    setState(() {});
  }

  double get _subTotal {
    final billable = _items.where((i) => !i.isReturned);
    // Inclusive (and GST regular) subtotal is the line total, not taxable value.
    if (_taxInclusive || _gstType == GstType.regular) {
      return billable.fold(0.0, (acc, i) => acc + i.totalAfterTax);
    }
    return billable.fold(0.0, (acc, i) => acc + i.total);
  }

  double get _discountAmount {
    final raw = double.tryParse(_discountValueController.text.trim()) ?? 0;
    if (raw <= 0) return 0;
    if (_discountIsPercentage) return _subTotal * (raw / 100);
    return raw;
  }

  double get _grandTotal => (_subTotal - _discountAmount).clamp(0, double.infinity);

  double get _creditAmount =>
      double.tryParse(_creditAmountController.text.trim()) ?? 0;

  double get _netPayable => (_grandTotal - _creditAmount).clamp(0, double.infinity);

  Future<void> _pickDate({
    required DateTime initial,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2018),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked == null) return;
    onPicked(DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _billTime,
    );
    if (picked == null) return;
    setState(() => _billTime = picked);
  }

  Future<void> _save() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A bill must have at least one item'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final firestore = FirebaseFirestore.instance;
      final billRef = firestore
          .collection('users')
          .doc(widget.userDocumentId)
          .collection('bills')
          .doc(widget.billDocId);

      final snap = await billRef.get();
      final rawItems = snap.data()?['items'];

      List<dynamic> originalList = [];
      if (rawItems is String) {
        final decoded = jsonDecode(rawItems);
        if (decoded is List) originalList = List<dynamic>.from(decoded);
      } else if (rawItems is List) {
        originalList = List<dynamic>.from(rawItems);
      }

      final patchedItems = <Map<String, dynamic>>[];
      for (var i = 0; i < _items.length; i++) {
        final draft = _items[i];
        draft.recalculate(taxInclusive: _taxInclusive);
        Map<String, dynamic> map;
        if (i < originalList.length && originalList[i] is Map) {
          map = Map<String, dynamic>.from(originalList[i] as Map);
        } else {
          map = draft.toBillItem().toMap();
        }
        map['name'] = draft.name.text.trim();
        map['code'] = draft.code.text.trim();
        map['hsn_code'] = draft.hsn.text.trim();
        map['unit'] = draft.unit.text.trim();
        map['category_code'] = draft.categoryCode.text.trim();
        map['price'] = draft.parseNum(draft.price);
        map['quantity'] = draft.parseNum(draft.quantity);
        map['return_quantity'] = draft.parseNum(draft.returnQuantity);
        map['tax_perc'] = draft.parseNum(draft.taxPerc);
        map['total'] = draft.total;
        map['total_after_tax'] = draft.totalAfterTax;
        map['is_returned'] = draft.isReturned ? 1 : 0;
        patchedItems.add(map);
      }

      final billDateTime = DateTime(
        _billDate.year,
        _billDate.month,
        _billDate.day,
        _billTime.hour,
        _billTime.minute,
      );
      final nowIso = DateTime.now().toIso8601String();

      final updateData = <String, dynamic>{
        'invoice_number': _invoiceController.text.trim(),
        'customer_code': _customerCodeController.text.trim(),
        'customer_name': _customerNameController.text.trim(),
        'customer_gst': _customerGstController.text.trim(),
        'customer_address': _customerAddressController.text.trim(),
        'type': _gstType.toString(),
        'payment_mode': _paymentMode.toString(),
        'credit_amount': _creditAmount,
        'discount': _discountAmount,
        'sub_total': _subTotal,
        'grand_total': _grandTotal,
        'net_payable': _netPayable,
        'total_items': _items.length,
        'bill_date': _billDate.toIso8601String(),
        'bill_time': billDateTime.toIso8601String(),
        'due_date': _dueDate.toIso8601String(),
        'items': rawItems is String ? jsonEncode(patchedItems) : patchedItems,
        'updated_at': nowIso,
      };

      await billRef.update(updateData);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bill updated'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update bill: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Bill · ${widget.bill.invoiceNumber}'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          _sectionTitle('Bill details'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _textField(_invoiceController, 'Invoice number'),
                  _textField(_customerCodeController, 'Customer code'),
                  _textField(_customerNameController, 'Customer name'),
                  _textField(_customerGstController, 'Customer GST'),
                  _textField(
                    _customerAddressController,
                    'Customer address',
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<GstType>(
                    value: _gstType,
                    decoration: const InputDecoration(
                      labelText: 'Bill type',
                      border: OutlineInputBorder(),
                    ),
                    items: GstType.values
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(t.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _gstType = v);
                      _recalculateAll();
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<PaymentModes>(
                    value: _paymentMode,
                    decoration: const InputDecoration(
                      labelText: 'Payment mode',
                      border: OutlineInputBorder(),
                    ),
                    items: PaymentModes.values
                        .map(
                          (m) => DropdownMenuItem(
                            value: m,
                            child: Text(m.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _paymentMode = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  _textField(
                    _creditAmountController,
                    'Credit amount',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Bill date'),
                    subtitle: Text(DateFormat('dd MMM yyyy').format(_billDate)),
                    trailing: const Icon(Icons.calendar_today_outlined),
                    onTap: () => _pickDate(
                      initial: _billDate,
                      onPicked: (d) => setState(() => _billDate = d),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Bill time'),
                    subtitle: Text(_billTime.format(context)),
                    trailing: const Icon(Icons.schedule_outlined),
                    onTap: _pickTime,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Due date'),
                    subtitle: Text(DateFormat('dd MMM yyyy').format(_dueDate)),
                    trailing: const Icon(Icons.event_outlined),
                    onTap: () => _pickDate(
                      initial: _dueDate,
                      onPicked: (d) => setState(() => _dueDate = d),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _sectionTitle('Items'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tax inclusive'),
            subtitle: Text(
              _taxInclusive
                  ? 'Price includes tax. Totals split tax from line amount.'
                  : 'Price is exclusive. Tax is added on top.',
            ),
            value: _taxInclusive,
            onChanged: (v) {
              _taxInclusive = v;
              _recalculateAll();
            },
          ),
          ...List.generate(_items.length, _buildItemCard),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _items.add(
                  _EditableItem(
                    BillItem(
                      billId: widget.bill.id ?? 0,
                      name: '',
                      hsnCode: '',
                      unit: '',
                      categoryCode: '',
                      code: '',
                      price: 0,
                      quantity: 1,
                      returnQuantity: 0,
                      total: 0,
                      taxPerc: 0,
                      totalAfterTax: 0,
                      isReturned: false,
                    ),
                  ),
                );
              });
            },
            icon: const Icon(Icons.add),
            label: const Text('Add item'),
          ),
          const SizedBox(height: 20),
          _sectionTitle('Discount'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter discount to deduct from subtotal, as percentage or amount.',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _discountValueController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            hintText: _discountIsPercentage
                                ? 'Discount percentage'
                                : 'Discount amount',
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<bool>(
                        value: _discountIsPercentage,
                        items: const [
                          DropdownMenuItem(value: true, child: Text('%')),
                          DropdownMenuItem(value: false, child: Text('₹')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _discountIsPercentage = v);
                        },
                      ),
                    ],
                  ),
                  if (_discountAmount > 0) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          _discountValueController.clear();
                          setState(() {});
                        },
                        child: const Text('Remove discount'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _sectionTitle('Totals'),
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _totalRow('Subtotal', _subTotal),
                  if (_discountAmount > 0)
                    _totalRow(
                      _discountIsPercentage
                          ? 'Discount (${_discountValueController.text}%)'
                          : 'Discount',
                      -_discountAmount,
                    ),
                  const Divider(),
                  _totalRow('Grand total', _grandTotal, bold: true),
                  if (_creditAmount > 0) _totalRow('Credit amount', _creditAmount),
                  _totalRow(
                    'Net payable',
                    _netPayable,
                    bold: true,
                    color: AppColors.primaryGreen,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text(_saving ? 'Saving…' : 'Save bill'),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _textField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _totalRow(String label, double amount, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
          Text(
            '₹${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard(int index) {
    final item = _items[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Item ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (_items.length > 1)
                  IconButton(
                    tooltip: 'Remove item',
                    onPressed: () {
                      setState(() {
                        item.dispose();
                        _items.removeAt(index);
                      });
                    },
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            _textField(item.name, 'Name', onChanged: (_) => setState(() {})),
            Row(
              children: [
                Expanded(child: _textField(item.code, 'Code')),
                const SizedBox(width: 8),
                Expanded(child: _textField(item.hsn, 'HSN')),
              ],
            ),
            Row(
              children: [
                Expanded(child: _textField(item.unit, 'Unit')),
                const SizedBox(width: 8),
                Expanded(child: _textField(item.categoryCode, 'Category code')),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _textField(
                    item.price,
                    'Price',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) {
                      item.recalculate(taxInclusive: _taxInclusive);
                      setState(() {});
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _textField(
                    item.quantity,
                    'Quantity',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) {
                      item.recalculate(taxInclusive: _taxInclusive);
                      setState(() {});
                    },
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _textField(
                    item.taxPerc,
                    'Tax %',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) {
                      item.recalculate(taxInclusive: _taxInclusive);
                      setState(() {});
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _textField(
                    item.returnQuantity,
                    'Return qty',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ],
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: item.isReturned,
              onChanged: (v) {
                setState(() => item.isReturned = v ?? false);
              },
              title: const Text('Returned item'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            Text(
              'Taxable: ₹${item.total.toStringAsFixed(2)}   '
              'After tax: ₹${item.totalAfterTax.toStringAsFixed(2)}',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.primaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
