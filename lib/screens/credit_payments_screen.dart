import 'package:flutter/material.dart';

class CreditPaymentsScreen extends StatelessWidget {
  final String userId;

  const CreditPaymentsScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Credit & Payments'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.payment, size: 64, color: Colors.indigo[300]),
            const SizedBox(height: 16),
            Text(
              'Credit & Payments for User',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text('User ID: $userId', style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 24),
            const Text('Credit & Payments feature coming soon...'),
          ],
        ),
      ),
    );
  }
}
