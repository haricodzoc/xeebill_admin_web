import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/credit_summary_model.dart';
import '../models/customer_info_model.dart';
import '../services/customer_credit_firestore_service.dart';

/// Per-customer balance sheet (Firestore): bills with credit, direct credits, debit payments.
class CustomerCreditBalanceScreen extends StatefulWidget {
  final String userDocumentId;
  final CustomerInfoModel customer;

  const CustomerCreditBalanceScreen({
    super.key,
    required this.userDocumentId,
    required this.customer,
  });

  @override
  State<CustomerCreditBalanceScreen> createState() => _CustomerCreditBalanceScreenState();
}

class _CustomerCreditBalanceScreenState extends State<CustomerCreditBalanceScreen> {
  final _svc = CustomerCreditFirestoreService.instance;
  late CustomerInfoModel _customer;
  int _refreshKey = 0;

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
  }

  Future<List<PaymentInfoModel>> _loadPayments() {
    return _svc.loadBalanceSheet(widget.userDocumentId, _customer);
  }

  Future<void> _reloadCustomer() async {
    final fresh = await _svc.fetchCustomer(widget.userDocumentId, _customer.code);
    if (fresh != null && mounted) {
      setState(() => _customer = fresh);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(_customer),
        ),
        titleSpacing: 0,
        title: const Text('Credits & Payments'),
      ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Credits & payments for ${_customer.name}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ExpansionTile(
                      initiallyExpanded: true,
                      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: Icon(Icons.credit_card_rounded, color: cs.primary),
                      title: Text(
                        'Payment details',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: cs.primary,
                            ),
                      ),
                      children: [
                        FutureBuilder<List<PaymentInfoModel>>(
                          key: ValueKey<int>(_refreshKey),
                          future: _loadPayments(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              );
                            }
                            if (snapshot.hasError) {
                              return Padding(
                                padding: const EdgeInsets.all(20),
                                child: Text(
                                  'Error loading payments: ${snapshot.error}',
                                  style: TextStyle(color: cs.error),
                                ),
                              );
                            }
                            final allPayments = snapshot.data ?? [];
                            double totalCredits = 0;
                            for (final p in allPayments.where((e) => e.isCredit)) {
                              totalCredits += p.actualAmount;
                            }
                            final totalDebits = allPayments
                                .where((e) => !e.isCredit)
                                .fold<double>(0, (s, e) => s + e.actualAmount);
                            final totalDue = totalCredits - totalDebits;

                            return Column(
                              children: [
                                if (allPayments.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Text(
                                      'No transactions found for this customer',
                                      style: TextStyle(color: cs.onSurfaceVariant),
                                    ),
                                  )
                                else
                                  ListView.separated(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: allPayments.length,
                                    separatorBuilder: (_, _) => const Divider(height: 1),
                                    itemBuilder: (context, index) {
                                      final p = allPayments[index];
                                      return _PaymentTile(payment: p);
                                    },
                                  ),
                                const Divider(thickness: 2),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                  child: Column(
                                    children: [
                                      _totalRow(context, 'Total credits:', totalCredits, Colors.red.shade700),
                                      const SizedBox(height: 4),
                                      _totalRow(context, 'Total debits:', totalDebits, Colors.green.shade700),
                                      const SizedBox(height: 8),
                                      Container(height: 1, color: Colors.grey.shade300),
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Total due:',
                                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                          Text(
                                            '₹${totalDue.toStringAsFixed(2)}',
                                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color: totalDue > 0
                                                      ? Colors.red.shade700
                                                      : totalDue < 0
                                                          ? Colors.green.shade700
                                                          : Colors.grey.shade600,
                                                ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      // SizedBox(
                                      //   width: double.infinity,
                                      //   child: FilledButton.icon(
                                      //     onPressed: () => _showAddPaymentDialog(
                                      //       context,
                                      //       totalCredits: totalCredits,
                                      //       totalDue: totalDue,
                                      //     ),
                                      //     icon: const Icon(Icons.add_rounded, size: 20),
                                      //     label: const Text('Add new payment'),
                                      //   ),
                                      // ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }

  Widget _totalRow(BuildContext context, String label, double value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(
          '₹${value.toStringAsFixed(2)}',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: valueColor,
              ),
        ),
      ],
    );
  }

  Future<void> _showAddPaymentDialog(
    BuildContext context, {
    required double totalCredits,
    required double totalDue,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _AddPaymentDialog(
        userDocumentId: widget.userDocumentId,
        customer: _customer,
        totalCredits: totalCredits,
        totalDue: totalDue,
        service: _svc,
        messenger: ScaffoldMessenger.of(context),
        onSuccess: () async {
          await _reloadCustomer();
          if (mounted) setState(() => _refreshKey++);
        },
      ),
    );
  }
}

/// Owns [TextEditingController]s and [ValueNotifier]s so they are disposed only after the route is removed
/// (avoids "used after being disposed" when the dialog exit animation is still running).
class _AddPaymentDialog extends StatefulWidget {
  final String userDocumentId;
  final CustomerInfoModel customer;
  final double totalCredits;
  final double totalDue;
  final CustomerCreditFirestoreService service;
  final ScaffoldMessengerState messenger;
  final Future<void> Function() onSuccess;

  const _AddPaymentDialog({
    required this.userDocumentId,
    required this.customer,
    required this.totalCredits,
    required this.totalDue,
    required this.service,
    required this.messenger,
    required this.onSuccess,
  });

  @override
  State<_AddPaymentDialog> createState() => _AddPaymentDialogState();
}

class _AddPaymentDialogState extends State<_AddPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _remarksController;
  late final ValueNotifier<DateTime?> _dueDateNotifier;
  late final ValueNotifier<String> _typeNotifier;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.totalDue > 0 ? widget.totalDue.toStringAsFixed(2) : '',
    );
    _remarksController = TextEditingController();
    _dueDateNotifier = ValueNotifier<DateTime?>(DateTime.now().add(const Duration(days: 7)));
    _typeNotifier = ValueNotifier<String>('debit');
  }

  @override
  void dispose() {
    _amountController.dispose();
    _remarksController.dispose();
    _dueDateNotifier.dispose();
    _typeNotifier.dispose();
    super.dispose();
  }

  Future<void> _submit(String selectedType) async {
    if (!_formKey.currentState!.validate()) return;
    if (selectedType == 'credit' && _dueDateNotifier.value == null) {
      widget.messenger.showSnackBar(const SnackBar(content: Text('Select a due date')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final amt = double.parse(_amountController.text.trim());
      final rem = _remarksController.text.trim();
      if (selectedType == 'debit') {
        final st = await widget.service.addDebitPayment(
          userDocId: widget.userDocumentId,
          customer: widget.customer,
          amount: amt,
          remarks: rem,
        );
        if (!mounted) return;
        if (st <= 0) {
          widget.messenger.showSnackBar(const SnackBar(content: Text('Could not save payment')));
        } else {
          widget.messenger.showSnackBar(const SnackBar(content: Text('Debit payment added')));
          await widget.onSuccess();
          if (mounted) Navigator.of(context).pop();
        }
      } else {
        final st = await widget.service.addDirectCredit(
          userDocId: widget.userDocumentId,
          customer: widget.customer,
          amount: amt,
          remarks: rem,
          dueDate: _dueDateNotifier.value!,
        );
        if (!mounted) return;
        if (st <= 0) {
          widget.messenger.showSnackBar(const SnackBar(content: Text('Could not add credit')));
        } else {
          widget.messenger.showSnackBar(const SnackBar(content: Text('Credit added')));
          await widget.onSuccess();
          if (mounted) Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        widget.messenger.showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: _typeNotifier,
      builder: (context, selectedType, _) {
        return AlertDialog(
          title: const Text('Add payment'),
          content: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'debit', label: Text('Debit'), icon: Icon(Icons.remove)),
                      ButtonSegment(value: 'credit', label: Text('Credit'), icon: Icon(Icons.add)),
                    ],
                    selected: {selectedType},
                    onSelectionChanged: (s) {
                      if (_submitting) return;
                      _typeNotifier.value = s.first;
                      if (s.first == 'debit') {
                        _amountController.text =
                            widget.totalDue > 0 ? widget.totalDue.toStringAsFixed(2) : '';
                      } else {
                        _amountController.clear();
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _amountController,
                    decoration: InputDecoration(
                      labelText: selectedType == 'debit' ? 'Debit amount' : 'Credit amount',
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Enter an amount';
                      }
                      final a = double.tryParse(v.trim());
                      if (a == null || a <= 0) return 'Invalid amount';
                      if (selectedType == 'debit' && a > widget.totalDue + 0.009) {
                        return 'Cannot exceed due ₹${widget.totalDue.toStringAsFixed(2)}';
                      }
                      return null;
                    },
                  ),
                  if (selectedType == 'credit') ...[
                    const SizedBox(height: 16),
                    ValueListenableBuilder<DateTime?>(
                      valueListenable: _dueDateNotifier,
                      builder: (context, due, _) {
                        final dt = due;
                        return InkWell(
                          onTap: _submitting
                              ? null
                              : () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: dt ?? DateTime.now(),
                                    firstDate: DateTime.now(),
                                    lastDate: DateTime.now().add(const Duration(days: 365)),
                                  );
                                  if (picked != null) _dueDateNotifier.value = picked;
                                },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Due date',
                              border: OutlineInputBorder(),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  dt != null ? DateFormat('dd MMM yyyy').format(dt) : 'Select date',
                                ),
                                const Icon(Icons.calendar_today, size: 18),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _remarksController,
                    decoration: const InputDecoration(
                      labelText: 'Remarks (optional)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _submitting ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _submitting ? null : () => _submit(selectedType),
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(selectedType == 'debit' ? 'Add debit' : 'Add credit'),
            ),
          ],
        );
      },
    );
  }
}

class _PaymentTile extends StatelessWidget {
  final PaymentInfoModel payment;

  const _PaymentTile({required this.payment});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isCredit = payment.isCredit;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (isCredit ? Colors.orange : Colors.green).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isCredit ? Icons.receipt_long : Icons.payments_outlined,
              size: 20,
              color: isCredit ? Colors.orange.shade800 : Colors.green.shade800,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payment.paymentId,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('dd MMM yyyy').format(payment.createdAt),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                if (payment.remarks.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    payment.remarks,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  'Balance after: ₹${payment.dueAmount.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isCredit ? '+' : '-'}₹${payment.actualAmount.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isCredit ? Colors.orange.shade800 : Colors.green.shade800,
                    ),
              ),
              const SizedBox(height: 4),
              Chip(
                label: Text(isCredit ? 'Credit' : 'Debit', style: const TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
