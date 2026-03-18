import 'package:flutter/material.dart';

class ReportsScreen extends StatelessWidget {
  final String userId;

  const ReportsScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Reports'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.analytics, size: 64, color: Colors.teal[300]),
            const SizedBox(height: 16),
            Text(
              'Reports for User',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text('User ID: $userId', style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 24),
            const Text('Reports feature coming soon...'),
          ],
        ),
      ),
    );
  }
}
