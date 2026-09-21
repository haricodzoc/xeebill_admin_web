import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/recharge_plan_model.dart';

class EditRechargePlanDialog extends StatefulWidget {
  final RechargePlanModel? plan;

  const EditRechargePlanDialog({super.key, this.plan});

  @override
  State<EditRechargePlanDialog> createState() => _EditRechargePlanDialogState();
}

class _EditRechargePlanDialogState extends State<EditRechargePlanDialog> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _subtitleController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _discountController = TextEditingController();
  final TextEditingController _durationController = TextEditingController();
  final TextEditingController _planIdController = TextEditingController();
  final TextEditingController _subscriptionIdController =
      TextEditingController();
  final TextEditingController _billsController = TextEditingController();
  final TextEditingController _customersController = TextEditingController();
  final TextEditingController _devicesController = TextEditingController();
  final TextEditingController _itemsController = TextEditingController();
  final TextEditingController _servicesController = TextEditingController();
  final TextEditingController _locationLimitController =
      TextEditingController(text: '1');
  final TextEditingController _backupYearController =
      TextEditingController(text: '0');

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.plan != null) {
      final plan = widget.plan!;
      _titleController.text = plan.title;
      _subtitleController.text = plan.subtitle;
      _priceController.text = plan.price.toString();
      _discountController.text = plan.discount.toString();
      _durationController.text = plan.durationInDays.toString();
      _planIdController.text = plan.planId;
      _subscriptionIdController.text = plan.subscriptionId;
      _billsController.text = plan.bills.toString();
      _customersController.text = plan.customers.toString();
      _devicesController.text = plan.devices.toString();
      _itemsController.text = plan.items.toString();
      _servicesController.text = plan.services.toString();
      _locationLimitController.text = plan.locationLimit.toString();
      _backupYearController.text = plan.backupYear.toString();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _subtitleController.dispose();
    _priceController.dispose();
    _discountController.dispose();
    _durationController.dispose();
    _planIdController.dispose();
    _subscriptionIdController.dispose();
    _billsController.dispose();
    _customersController.dispose();
    _devicesController.dispose();
    _itemsController.dispose();
    _servicesController.dispose();
    _locationLimitController.dispose();
    _backupYearController.dispose();
    super.dispose();
  }

  String? _requiredIntValidator(String? value, {required String label}) {
    if (value == null || value.trim().isEmpty) {
      return '$label is required';
    }
    if (int.tryParse(value.trim()) == null) {
      return 'Enter a valid whole number';
    }
    return null;
  }

  Future<void> _savePlan() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final planData = {
        'title': _titleController.text.trim(),
        'subtitle': _subtitleController.text.trim(),
        'price': int.parse(_priceController.text.trim()),
        'discount': int.parse(_discountController.text.trim()),
        'duration_in_days': int.parse(_durationController.text.trim()),
        'plan_id': _planIdController.text.trim(),
        'subscription_id': _subscriptionIdController.text.trim(),
        'bills': int.parse(_billsController.text.trim()),
        'customers': int.parse(_customersController.text.trim()),
        'devices': int.parse(_devicesController.text.trim()),
        'items': int.parse(_itemsController.text.trim()),
        'services': int.parse(_servicesController.text.trim()),
        'location_limit':
            int.tryParse(_locationLimitController.text.trim()) ?? 1,
        'backup_year':
            int.tryParse(_backupYearController.text.trim()) ?? 0,
      };

      if (widget.plan != null) {
        await _firestore
            .collection('recharge_plans')
            .doc(widget.plan!.id)
            .update(planData);
      } else {
        await _firestore.collection('recharge_plans').add(planData);
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.plan != null
                  ? 'Plan updated successfully'
                  : 'Plan created successfully',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving plan: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _intField({
    required TextEditingController controller,
    required String label,
    String? suffix,
    String? prefix,
    bool required = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          border: const OutlineInputBorder(),
          suffixText: suffix,
          prefixText: prefix,
        ),
        keyboardType: TextInputType.number,
        validator: required
            ? (value) => _requiredIntValidator(value, label: label)
            : (value) {
                if (value == null || value.trim().isEmpty) return null;
                if (int.tryParse(value.trim()) == null) {
                  return 'Enter a valid whole number';
                }
                return null;
              },
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    int maxLines = 1,
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          border: const OutlineInputBorder(),
          alignLabelWithHint: maxLines > 1,
        ),
        validator: required
            ? (value) =>
                value?.trim().isEmpty ?? true ? '$label is required' : null
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92,
          maxWidth: 560,
        ),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    widget.plan != null ? 'Edit Plan' : 'Create New Plan',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle('Plan details'),
                      _textField(
                        controller: _titleController,
                        label: 'Title',
                        required: true,
                      ),
                      _textField(
                        controller: _subtitleController,
                        label: 'Subtitle',
                        maxLines: 3,
                      ),
                      _intField(
                        controller: _priceController,
                        label: 'Price',
                        prefix: '₹ ',
                      ),
                      _intField(
                        controller: _discountController,
                        label: 'Discount',
                        suffix: '%',
                      ),
                      _intField(
                        controller: _durationController,
                        label: 'Duration in days',
                        suffix: 'days',
                      ),
                      _sectionTitle('Identifiers'),
                      _textField(
                        controller: _planIdController,
                        label: 'Plan ID',
                      ),
                      _textField(
                        controller: _subscriptionIdController,
                        label: 'Subscription ID',
                      ),
                      _sectionTitle('Plan limits'),
                      _intField(
                        controller: _billsController,
                        label: 'Bills',
                      ),
                      _intField(
                        controller: _customersController,
                        label: 'Customers',
                      ),
                      _intField(
                        controller: _devicesController,
                        label: 'Devices',
                      ),
                      _intField(
                        controller: _itemsController,
                        label: 'Items',
                      ),
                      _intField(
                        controller: _servicesController,
                        label: 'Services',
                      ),
                      _intField(
                        controller: _locationLimitController,
                        label: 'Location limit',
                        required: false,
                      ),
                      _intField(
                        controller: _backupYearController,
                        label: 'Backup year',
                        suffix: 'years',
                        required: false,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _savePlan,
                      child: _isSaving
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
                          : Text(widget.plan != null ? 'Update' : 'Create'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
