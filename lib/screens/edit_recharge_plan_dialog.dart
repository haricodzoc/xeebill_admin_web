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

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.plan != null) {
      _titleController.text = widget.plan!.title;
      _subtitleController.text = widget.plan!.subtitle;
      _priceController.text = widget.plan!.price.toStringAsFixed(2);
      _discountController.text = widget.plan!.discount.toStringAsFixed(1);
      _durationController.text = widget.plan!.durationInDays.toString();
      _planIdController.text = widget.plan!.planId;
      _subscriptionIdController.text = widget.plan!.subscriptionId;
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
    super.dispose();
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
        'price': double.tryParse(_priceController.text) ?? 0.0,
        'discount': double.tryParse(_discountController.text) ?? 0.0,
        'duration_in_days': int.tryParse(_durationController.text) ?? 0,
        'plan_id': _planIdController.text.trim(),
        'subscription_id': _subscriptionIdController.text.trim(),
      };

      if (widget.plan != null) {
        // Update existing plan
        await _firestore
            .collection('recharge_plans')
            .doc(widget.plan!.id)
            .update(planData);
      } else {
        // Create new plan
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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
          maxWidth: 500,
        ),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
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
              // Form fields
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      TextFormField(
                        controller: _titleController,
                        decoration: const InputDecoration(
                          labelText: 'Title *',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            value?.isEmpty ?? true ? 'Title is required' : null,
                      ),
                      const SizedBox(height: 16),
                      // Subtitle
                      TextFormField(
                        controller: _subtitleController,
                        decoration: const InputDecoration(
                          labelText: 'Subtitle',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Price
                      TextFormField(
                        controller: _priceController,
                        decoration: const InputDecoration(
                          labelText: 'Price *',
                          border: OutlineInputBorder(),
                          prefixText: '₹ ',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (value) {
                          if (value?.isEmpty ?? true) {
                            return 'Price is required';
                          }
                          if (double.tryParse(value!) == null) {
                            return 'Please enter a valid number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      // Discount
                      TextFormField(
                        controller: _discountController,
                        decoration: const InputDecoration(
                          labelText: 'Discount (%) *',
                          border: OutlineInputBorder(),
                          suffixText: '%',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (value) {
                          if (value?.isEmpty ?? true) {
                            return 'Discount is required';
                          }
                          if (double.tryParse(value!) == null) {
                            return 'Please enter a valid number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      // Duration in days
                      TextFormField(
                        controller: _durationController,
                        decoration: const InputDecoration(
                          labelText: 'Duration (Days) *',
                          border: OutlineInputBorder(),
                          suffixText: 'days',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value?.isEmpty ?? true) {
                            return 'Duration is required';
                          }
                          if (int.tryParse(value!) == null) {
                            return 'Please enter a valid number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      // Plan ID
                      TextFormField(
                        controller: _planIdController,
                        decoration: const InputDecoration(
                          labelText: 'Plan ID',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Subscription ID
                      TextFormField(
                        controller: _subscriptionIdController,
                        decoration: const InputDecoration(
                          labelText: 'Subscription ID',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Buttons
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
