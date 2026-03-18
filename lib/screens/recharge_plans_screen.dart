import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/recharge_plan_model.dart';
import 'edit_recharge_plan_dialog.dart';
import '../utils/app_colors.dart';

class RechargePlansScreen extends StatefulWidget {
  const RechargePlansScreen({super.key});

  @override
  State<RechargePlansScreen> createState() => _RechargePlansScreenState();
}

class _RechargePlansScreenState extends State<RechargePlansScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = true;
  String? _errorMessage;
  List<RechargePlanModel> _plans = [];

  @override
  void initState() {
    super.initState();
    _fetchPlans();
  }

  Future<void> _fetchPlans() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final plansSnapshot = await _firestore
          .collection('recharge_plans')
          .orderBy('price')
          .get();

      final List<RechargePlanModel> plans = [];
      for (var doc in plansSnapshot.docs) {
        try {
          final plan = RechargePlanModel.fromFirestore(doc);
          plans.add(plan);
        } catch (e) {
          debugPrint('Error parsing plan ${doc.id}: $e');
        }
      }

      setState(() {
        _plans = plans;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error fetching plans: $e';
        _isLoading = false;
      });
      debugPrint('Error fetching plans: $e');
    }
  }

  Future<void> _deletePlan(RechargePlanModel plan) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Plan'),
        content: Text('Are you sure you want to delete "${plan.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _firestore.collection('recharge_plans').doc(plan.id).delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Plan deleted successfully')),
          );
          _fetchPlans();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error deleting plan: $e')));
        }
      }
    }
  }

  void _showEditPlanDialog(RechargePlanModel? plan) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => EditRechargePlanDialog(plan: plan),
    );

    if (result == true && mounted) {
      _fetchPlans();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Recharge Plans'),
            if (!_isLoading && _plans.isNotEmpty)
              Text(
                '${_plans.length} plan${_plans.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchPlans,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showEditPlanDialog(null),
            tooltip: 'Add New Plan',
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    const Text('Loading recharge plans...'),
                  ],
                ),
              )
            : _errorMessage != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red[300],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red[700]),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _fetchPlans,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : _plans.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.phone_android_outlined,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No recharge plans found',
                      style: TextStyle(color: Colors.grey[600], fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap the + button to add a new plan',
                      style: TextStyle(color: Colors.grey[500], fontSize: 14),
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: _fetchPlans,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  itemCount: _plans.length,
                  itemBuilder: (context, index) {
                    final plan = _plans[index];
                    return _buildPlanCard(plan);
                  },
                ),
              ),
      ),
    );
  }

  Widget _buildPlanCard(RechargePlanModel plan) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (plan.subtitle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          plan.subtitle,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton(
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 20),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, size: 20, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (value) {
                    if (value == 'edit') {
                      _showEditPlanDialog(plan);
                    } else if (value == 'delete') {
                      _deletePlan(plan);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _buildInfoChip(
                  Icons.currency_rupee,
                  '₹${plan.price.toStringAsFixed(2)}',
                ),
                _buildInfoChip(
                  Icons.percent,
                  '${plan.discount.toStringAsFixed(1)}% off',
                ),
                _buildInfoChip(
                  Icons.calendar_today,
                  '${plan.durationInDays} days',
                ),
              ],
            ),
            if (plan.planId.isNotEmpty || plan.subscriptionId.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              if (plan.planId.isNotEmpty) _buildInfoRow('Plan ID', plan.planId),
              if (plan.subscriptionId.isNotEmpty)
                _buildInfoRow('Subscription ID', plan.subscriptionId),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.black87, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Chip(
      avatar: Icon(icon, size: 16, color: AppColors.primaryGreen),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey[700],
          fontWeight: FontWeight.w500,
        ),
      ),
      backgroundColor: AppColors.primaryGreen.withOpacity(0.1),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}
