import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/customer_info_model.dart';
import '../models/user_model.dart';

class UserCustomersScreen extends StatefulWidget {
  final UserModel user;

  const UserCustomersScreen({
    super.key,
    required this.user,
  });

  @override
  State<UserCustomersScreen> createState() => _UserCustomersScreenState();
}

class _UserCustomersScreenState extends State<UserCustomersScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<DocumentReference<Map<String, dynamic>>?> _resolveUserDocRef(
    UserModel user,
  ) async {
    final listedDocId = user.docId?.trim();
    if (listedDocId != null && listedDocId.isNotEmpty) {
      final ref = _firestore.collection('users').doc(listedDocId);
      final snap = await ref.get();
      if (snap.exists) return ref;
    }

    final uid = user.userId?.trim();
    if (uid != null && uid.isNotEmpty) {
      final byId = _firestore.collection('users').doc(uid);
      final snap = await byId.get();
      if (snap.exists) return byId;

      final q = await _firestore
          .collection('users')
          .where('userId', isEqualTo: uid)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) return q.docs.first.reference;
    }

    final email = user.email?.trim();
    if (email != null && email.isNotEmpty) {
      final q = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) return q.docs.first.reference;
    }

    return null;
  }

  bool _matches(CustomerInfoModel c) {
    if (_searchQuery.isEmpty) return true;
    final q = _searchQuery;
    return c.name.toLowerCase().contains(q) ||
        c.phone.toLowerCase().contains(q) ||
        c.code.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final userName = (widget.user.name ?? 'User').trim();

    return Scaffold(
      appBar: AppBar(
        title: Text('Customers • $userName'),
      ),
      body: FutureBuilder<DocumentReference<Map<String, dynamic>>?>(
        future: _resolveUserDocRef(widget.user),
        builder: (context, refSnap) {
          if (refSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (refSnap.hasError) {
            return Center(child: Text('Error: ${refSnap.error}'));
          }

          final userRef = refSnap.data;
          if (userRef == null) {
            return const Center(
              child: Text('Unable to find this user document'),
            );
          }

          final customersQuery = userRef.collection('customer_info');

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by name / phone / code',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () => _searchController.clear(),
                            icon: const Icon(Icons.close),
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: customersQuery.snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }

                    final docs = snapshot.data?.docs ?? [];
                    final customers = docs
                        .map((d) => CustomerInfoModel.fromMap(d.data()))
                        .where(_matches)
                        .toList();

                    customers.sort((a, b) {
                      final an = a.name.toLowerCase();
                      final bn = b.name.toLowerCase();
                      return an.compareTo(bn);
                    });

                    if (customers.isEmpty) {
                      return Center(
                        child: Text(
                          _searchQuery.isEmpty
                              ? 'No customers found'
                              : 'No matching customers',
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: customers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final c = customers[i];
                        final subtitle = <String>[
                          if (c.code.trim().isNotEmpty) 'Code: ${c.code}',
                          if (c.phone.trim().isNotEmpty) 'Phone: ${c.phone}',
                          'Due: ${c.totalDue.toStringAsFixed(2)}',
                        ].join('  •  ');

                        return Card(
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            title: Text(
                              c.name.isEmpty ? 'Unnamed Customer' : c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              showDialog<void>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: Text(
                                    c.name.isEmpty ? 'Customer' : c.name,
                                  ),
                                  content: SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('Code: ${c.code}'),
                                        Text('Phone: ${c.phone}'),
                                        Text('GST: ${c.gstNo}'),
                                        Text('Type: ${c.type}'),
                                        const SizedBox(height: 8),
                                        Text('Address: ${c.address}'),
                                        const SizedBox(height: 8),
                                        Text('Remarks: ${c.remarks}'),
                                        const SizedBox(height: 12),
                                        Text(
                                          'Total Credit: ${c.totalCredit.toStringAsFixed(2)}',
                                        ),
                                        Text(
                                          'Total Debit: ${c.totalDebit.toStringAsFixed(2)}',
                                        ),
                                        Text(
                                          'Total Due: ${c.totalDue.toStringAsFixed(2)}',
                                        ),
                                        Text('Total Visits: ${c.totalVisits}'),
                                      ],
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context),
                                      child: const Text('Close'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

