import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:xeebill_web/screens/settings_screen.dart';
import '../models/user_model.dart';
import 'bills_screen.dart';
import 'categories_screen.dart';
import 'items_screen.dart';
import 'sub_profiles_screen.dart';
import 'reports_screen.dart';
import 'credit_payments_screen.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isLoading = true;
  String? _errorMessage;
  List<UserModel> _users = [];
  bool _isAdmin = false;
  bool _isCheckingAdmin = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _checkAdminAndFetchUsers();
  }

  Future<void> _checkAdminAndFetchUsers() async {
    setState(() {
      _isLoading = true;
      _isCheckingAdmin = true;
      _errorMessage = null;
    });

    try {
      // Get current user
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        setState(() {
          _errorMessage = 'User not authenticated. Please login again.';
          _isLoading = false;
          _isCheckingAdmin = false;
        });
        return;
      }

      debugPrint('=== Checking Admin Access ===');
      debugPrint('Current User UID: ${currentUser.uid}');
      debugPrint('Current User Email: ${currentUser.email}');

      // Check if user has special email access (hello@codzoc.com)
      // This user can access all users without needing a Firestore document
      if (currentUser.email?.toLowerCase() == 'hello@codzoc.com') {
        debugPrint('✓ Special email access granted: hello@codzoc.com');
        setState(() {
          _isAdmin = true;
          _isCheckingAdmin = false;
        });
        await _fetchUsers();
        return;
      }

      // Try multiple methods to find user document
      DocumentSnapshot? userDocSnapshot;
      String? errorDetails;
      List<String> attemptedMethods = [];

      // Method 1: Try getting document directly by ID (if document ID = userId)
      attemptedMethods.add('Document ID (${currentUser.uid})');
      try {
        userDocSnapshot = await _firestore
            .collection('users')
            .doc(currentUser.uid)
            .get();
        if (userDocSnapshot.exists) {
          debugPrint('✓ Found user by document ID: ${currentUser.uid}');
        } else {
          debugPrint('✗ Document with ID ${currentUser.uid} does not exist');
        }
      } catch (e) {
        debugPrint('✗ Method 1 failed (document ID): $e');
        errorDetails = 'Document ID lookup failed: $e';
      }

      // Method 2: Try querying by userId field
      if (userDocSnapshot == null || !userDocSnapshot.exists) {
        attemptedMethods.add('userId field query');
        try {
          debugPrint('Trying to query by userId field: ${currentUser.uid}');
          final userQuery = await _firestore
              .collection('users')
              .where('userId', isEqualTo: currentUser.uid)
              .limit(1)
              .get();

          debugPrint('Query returned ${userQuery.docs.length} documents');
          if (userQuery.docs.isNotEmpty) {
            userDocSnapshot = userQuery.docs.first;
            debugPrint('✓ Found user by userId field: ${currentUser.uid}');
            debugPrint('  Document ID: ${userDocSnapshot.id}');
          } else {
            debugPrint('✗ No documents found with userId = ${currentUser.uid}');
          }
        } catch (queryError) {
          debugPrint('✗ Method 2 failed (userId field): $queryError');
          errorDetails = errorDetails != null
              ? '$errorDetails | Query by userId failed: $queryError'
              : 'Query by userId failed: $queryError';
        }
      }

      // Method 3: Try querying by email (since we know the email from auth)
      if ((userDocSnapshot == null || !userDocSnapshot.exists) &&
          currentUser.email != null) {
        attemptedMethods.add('email field query');
        try {
          debugPrint('Trying to query by email: ${currentUser.email}');
          final emailQuery = await _firestore
              .collection('users')
              .where('email', isEqualTo: currentUser.email)
              .limit(1)
              .get();

          debugPrint(
            'Email query returned ${emailQuery.docs.length} documents',
          );
          if (emailQuery.docs.isNotEmpty) {
            userDocSnapshot = emailQuery.docs.first;
            debugPrint('✓ Found user by email: ${currentUser.email}');
            debugPrint('  Document ID: ${userDocSnapshot.id}');
          } else {
            debugPrint(
              '✗ No documents found with email = ${currentUser.email}',
            );
          }
        } catch (emailError) {
          debugPrint('✗ Method 3 failed (email): $emailError');
          errorDetails = errorDetails != null
              ? '$errorDetails | Query by email failed: $emailError'
              : 'Query by email failed: $emailError';
        }
      }

      // Method 4: Fallback - Try fetching all users and finding current user
      if ((userDocSnapshot == null || !userDocSnapshot.exists)) {
        attemptedMethods.add('fetch all users and search');
        try {
          debugPrint(
            'Trying fallback: Fetching all users to find current user...',
          );
          final allUsersQuery = await _firestore.collection('users').get();
          debugPrint('Fetched ${allUsersQuery.docs.length} total users');

          // Try to find user by userId field, email, or document ID
          for (var doc in allUsersQuery.docs) {
            final data = doc.data();
            final docUserId = data['userId']?.toString();
            final docEmail = data['email']?.toString().toLowerCase();
            final currentEmail = currentUser.email?.toLowerCase();

            if (docUserId == currentUser.uid ||
                docEmail == currentEmail ||
                doc.id == currentUser.uid) {
              userDocSnapshot = doc;
              debugPrint('✓ Found user in all users list');
              debugPrint('  Document ID: ${doc.id}');
              debugPrint('  userId field: ${data['userId']}');
              debugPrint('  email field: ${data['email']}');
              break;
            }
          }

          if (userDocSnapshot == null || !userDocSnapshot.exists) {
            debugPrint(
              '✗ User not found in any of the ${allUsersQuery.docs.length} users',
            );
            debugPrint('  Searched for:');
            debugPrint('    - Document ID: ${currentUser.uid}');
            debugPrint('    - userId field: ${currentUser.uid}');
            debugPrint('    - email field: ${currentUser.email}');
            debugPrint('  Sample of available users (first 3):');
            for (var doc in allUsersQuery.docs.take(3)) {
              final data = doc.data();
              debugPrint(
                '    - Doc ID: ${doc.id}, userId: ${data['userId']}, email: ${data['email']}',
              );
            }
          }
        } catch (fallbackError) {
          debugPrint('✗ Fallback method failed: $fallbackError');
          errorDetails = errorDetails != null
              ? '$errorDetails | Fallback failed: $fallbackError'
              : 'Fallback failed: $fallbackError';
        }
      }

      if (userDocSnapshot == null || !userDocSnapshot.exists) {
        debugPrint('=== USER NOT FOUND ===');
        debugPrint('Attempted methods: ${attemptedMethods.join(", ")}');
        setState(() {
          _errorMessage =
              'User profile not found in Firestore.\n\n'
              'Looking for user with:\n'
              '• UID: ${currentUser.uid}\n'
              '• Email: ${currentUser.email ?? "N/A"}\n\n'
              'Methods attempted:\n'
              '${attemptedMethods.map((m) => '• $m').join("\n")}\n\n'
              'Please ensure:\n'
              '1. Your user document exists in the "users" collection\n'
              '2. The document has either:\n'
              '   - Document ID = ${currentUser.uid}, OR\n'
              '   - userId field = ${currentUser.uid}, OR\n'
              '   - email field = ${currentUser.email ?? "N/A"}\n'
              '3. Your Firestore rules allow reading the users collection\n\n'
              '${errorDetails != null ? "Errors:\n$errorDetails" : ""}';
          _isLoading = false;
          _isCheckingAdmin = false;
          _isAdmin = false;
        });
        return;
      }

      final currentUserData = UserModel.fromFirestore(userDocSnapshot);
      final userRole = currentUserData.role?.toUpperCase();

      if (userRole != 'ADMIN') {
        setState(() {
          _errorMessage =
              'Access denied. Admin role required to view customers.';
          _isLoading = false;
          _isCheckingAdmin = false;
          _isAdmin = false;
        });
        return;
      }

      // User is admin, proceed to fetch all users
      setState(() {
        _isAdmin = true;
        _isCheckingAdmin = false;
      });

      await _fetchUsers();
    } catch (e) {
      setState(() {
        _errorMessage = 'Error checking admin access: $e';
        _isLoading = false;
        _isCheckingAdmin = false;
        _isAdmin = false;
      });
    }
  }

  Future<void> _fetchUsers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      debugPrint('Fetching all users from Firestore...');
      final QuerySnapshot snapshot = await _firestore.collection('users').get();

      debugPrint('Found ${snapshot.docs.length} users');

      final List<UserModel> users = snapshot.docs
          .map((doc) {
            try {
              return UserModel.fromFirestore(doc);
            } catch (e) {
              debugPrint('Error parsing user document ${doc.id}: $e');
              return null;
            }
          })
          .whereType<UserModel>()
          .toList();

      // Sort users by name for better UX
      users.sort((a, b) {
        final nameA = a.name ?? '';
        final nameB = b.name ?? '';
        return nameA.compareTo(nameB);
      });

      setState(() {
        _users = users;
        _isLoading = false;
      });

      debugPrint('Successfully loaded ${users.length} users');
    } catch (e) {
      debugPrint('Error fetching users: $e');
      setState(() {
        _errorMessage =
            'Error fetching users: $e\n\nPlease check:\n'
            '• Your Firestore rules allow admin access\n'
            '• You have an active internet connection\n'
            '• Your user has ADMIN role';
        _isLoading = false;
      });
    }
  }

  List<UserModel> get _filteredUsers {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _users;

    return _users.where((u) {
      final name = (u.name ?? '').toLowerCase();
      final email = (u.email ?? '').toLowerCase();
      return name.contains(query) || email.contains(query);
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Customers'),
            if (!_isLoading && _users.isNotEmpty)
              Text(
                '${_filteredUsers.length} user${_filteredUsers.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        actions: [
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _checkAdminAndFetchUsers,
            ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  if (_isCheckingAdmin) ...[
                    const SizedBox(height: 16),
                    const Text('Checking admin access...'),
                  ],
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
                    Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.red[700]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    if (!_isAdmin)
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        child: const Text('Go Back'),
                      )
                    else
                      ElevatedButton(
                        onPressed: _checkAdminAndFetchUsers,
                        child: const Text('Retry'),
                      ),
                  ],
                ),
              ),
            )
          : _users.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No users found',
                    style: TextStyle(color: Colors.grey[600], fontSize: 18),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _fetchUsers,
              child: Column(
                children: [
                  // Search bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search by name or email',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setState(() {
                                    _searchQuery = '';
                                    _searchController.clear();
                                  });
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                    ),
                  ),
                  // Summary Card
                  if (_users.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Builder(
                        builder: (context) {
                          final now = DateTime.now();
                          final soonThreshold = now.add(
                            const Duration(days: 7),
                          );

                          final expiredCount = _filteredUsers
                              .where(
                                (u) =>
                                    u.accountExpiry != null &&
                                    u.accountExpiry!.isBefore(now),
                              )
                              .length;

                          final expiringSoonCount = _filteredUsers.where((u) {
                            final expiry = u.accountExpiry;
                            if (expiry == null) return false;
                            return !expiry.isBefore(now) &&
                                expiry.isBefore(soonThreshold);
                          }).length;

                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildSummaryItem(
                                context,
                                'Total Users',
                                _filteredUsers.length.toString(),
                                Icons.people,
                              ),
                              _buildSummaryItem(
                                context,
                                'Admins',
                                _filteredUsers
                                    .where(
                                      (u) => u.role?.toUpperCase() == 'ADMIN',
                                    )
                                    .length
                                    .toString(),
                                Icons.admin_panel_settings,
                              ),
                              _buildSummaryItem(
                                context,
                                'Expiring < 7d',
                                expiringSoonCount.toString(),
                                Icons.access_time,
                                Colors.orange,
                              ),
                              _buildSummaryItem(
                                context,
                                'Expired',
                                expiredCount.toString(),
                                Icons.warning,
                                Colors.red,
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  // Users List
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      itemCount: _filteredUsers.length,
                      itemBuilder: (context, index) {
                        return _buildUserCard(_filteredUsers[index]);
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildUserCard(UserModel user) {
    final now = DateTime.now();
    final expiry = user.accountExpiry;
    final isExpired = expiry != null && expiry.isBefore(now);
    final isExpiringSoon =
        expiry != null &&
        !isExpired &&
        expiry.isBefore(now.add(const Duration(days: 7)));
    final activeDevice = (user.activeDevice ?? '').trim();
    final hasActiveDevice = activeDevice.isNotEmpty;
    final expiryText = user.formatDate(user.accountExpiry);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(
            horizontal: 16.0,
            vertical: 8.0,
          ),
          childrenPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: isExpired
                ? Colors.red[300]
                : isExpiringSoon
                ? Colors.orange[300]
                : Theme.of(context).colorScheme.primary,
            child: Text(
              user.name?.substring(0, 1).toUpperCase() ?? 'U',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: Text(
            user.name ?? 'Unknown',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (user.email != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.email, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        user.email!,
                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.event,
                    size: 16,
                    color: isExpired
                        ? Colors.red[700]
                        : isExpiringSoon
                        ? Colors.orange[700]
                        : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${isExpired ? 'Expired' : 'Expiry'}: $expiryText',
                      style: TextStyle(
                        color: isExpired
                            ? Colors.red[700]
                            : isExpiringSoon
                            ? Colors.orange[700]
                            : Colors.grey[700],
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              if (hasActiveDevice) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.phone_iphone,
                      size: 16,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        activeDevice,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
              if (user.role != null) ...[
                const SizedBox(height: 4),
                Chip(
                  label: Text(user.role!, style: const TextStyle(fontSize: 11)),
                  backgroundColor: user.role == 'ADMIN'
                      ? Colors.blue[100]
                      : Colors.grey[200],
                  padding: EdgeInsets.zero,
                ),
              ],
            ],
          ),
          trailing: isExpired
              ? Icon(Icons.warning, color: Colors.red[700])
              : isExpiringSoon
              ? Icon(Icons.warning, color: Colors.orange[700])
              : const Icon(Icons.chevron_right),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow('User ID', user.userId ?? 'N/A'),
                  _buildInfoRow('Phone', user.phone ?? 'N/A'),
                  _buildInfoRow('Address', user.address ?? 'N/A'),
                  _buildInfoRow('GST Number', user.gstNumber ?? 'N/A'),
                  _buildActiveDeviceRow(user),
                  _buildAccountExpiryRow(user),
                  _buildInfoRow('Created At', user.formatDate(user.createdAt)),
                  _buildInfoRow('Updated At', user.formatDate(user.updatedAt)),
                  _buildInfoRow('Last Login', user.formatDate(user.lastLogin)),
                  _buildInfoRow(
                    'Last Sync Time',
                    user.formatDate(user.lastSyncTime),
                  ),
                  _buildInfoRow(
                    'Bill Version',
                    user.billVersion?.toString() ?? 'N/A',
                  ),
                  _buildInfoRow(
                    'Item Version',
                    user.itemVersion?.toString() ?? 'N/A',
                  ),
                  _buildInfoRow(
                    'Reset Sync Time',
                    user.resetSyncTime?.toString() ?? 'N/A',
                  ),
                  _buildInfoRow(
                    'Upload Error Log',
                    user.uploadErrorLog?.toString() ?? 'N/A',
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),
                  const Text(
                    'Quick Actions',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildActionButton(
                        context,
                        'View Bills',
                        Icons.receipt_long,
                        Colors.blue,
                        () => _navigateToBills(context, user),
                      ),
                      _buildActionButton(
                        context,
                        'Categories',
                        Icons.category,
                        Colors.green,
                        () => _navigateToCategories(context, user),
                      ),
                      _buildActionButton(
                        context,
                        'Items',
                        Icons.inventory_2,
                        Colors.orange,
                        () => _navigateToItems(context, user),
                      ),
                      _buildActionButton(
                        context,
                        'Sub Profiles',
                        Icons.people_outline,
                        Colors.purple,
                        () => _navigateToSubProfiles(context, user),
                      ),
                      _buildActionButton(
                        context,
                        'Reports',
                        Icons.analytics,
                        Colors.teal,
                        () => _navigateToReports(context, user),
                      ),
                      _buildActionButton(
                        context,
                        'Credit & Payments',
                        Icons.payment,
                        Colors.indigo,
                        () => _navigateToCreditPayments(context, user),
                      ),
                      _buildActionButton(
                        context,
                        'Settings',
                        Icons.settings,
                        Colors.grey,
                        () => _navigateToSettings(context, user),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.1),
        foregroundColor: color,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: color.withOpacity(0.3)),
        ),
      ),
    );
  }

  void _navigateToBills(BuildContext context, UserModel user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BillsScreen(userId: user.userId ?? ''),
      ),
    );
  }

  void _navigateToCategories(BuildContext context, UserModel user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CategoriesScreen(userId: user.userId ?? ''),
      ),
    );
  }

  void _navigateToItems(BuildContext context, UserModel user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ItemsScreen(userId: user.userId ?? ''),
      ),
    );
  }

  void _navigateToSubProfiles(BuildContext context, UserModel user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SubProfilesScreen(userId: user.userId ?? ''),
      ),
    );
  }

  void _navigateToReports(BuildContext context, UserModel user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReportsScreen(userId: user.userId ?? ''),
      ),
    );
  }

  void _navigateToCreditPayments(BuildContext context, UserModel user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreditPaymentsScreen(userId: user.userId ?? ''),
      ),
    );
  }

  void _navigateToSettings(BuildContext context, UserModel user) {
    // TODO: Navigate to settings screen when available
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => SettingsScreen()),
    );
  }

  Widget _buildSummaryItem(
    BuildContext context,
    String label,
    String value,
    IconData icon, [
    Color? color,
  ]) {
    final themeColor = color ?? Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        Icon(icon, color: themeColor, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: themeColor,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, [Color? valueColor]) {
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
              style: TextStyle(
                color: valueColor ?? Colors.black87,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveDeviceRow(UserModel user) {
    final activeDevice = (user.activeDevice ?? '').trim();
    final hasDevice = activeDevice.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              'Active Device:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    hasDevice ? activeDevice : 'N/A',
                    style: const TextStyle(color: Colors.black87, fontSize: 13),
                  ),
                ),
                if (hasDevice)
                  TextButton(
                    onPressed: () => _confirmAndClearActiveDevice(user),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      foregroundColor: Colors.red[700],
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Clear'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountExpiryRow(UserModel user) {
    final now = DateTime.now();
    final expiry = user.accountExpiry;
    final isExpired = expiry != null && expiry.isBefore(now);
    final isExpiringSoon =
        expiry != null &&
        !isExpired &&
        expiry.isBefore(now.add(const Duration(days: 7)));
    final expiryText = user.formatDate(user.accountExpiry);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              'Account Expiry:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    expiryText,
                    style: TextStyle(
                      color: isExpired
                          ? Colors.red[700]
                          : isExpiringSoon
                          ? Colors.orange[700]
                          : Colors.black87,
                      fontSize: 13,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _resetExpiryDate(user),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    foregroundColor: Colors.blue[700],
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Reset'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<DocumentReference<Map<String, dynamic>>?> _resolveUserDocRef(
    UserModel user,
  ) async {
    // 1) Try doc(userId) (common pattern)
    final uid = user.userId?.trim();
    if (uid != null && uid.isNotEmpty) {
      final byId = _firestore.collection('users').doc(uid);
      final snap = await byId.get();
      if (snap.exists) return byId;

      // 2) Fallback: query by userId field
      final q = await _firestore
          .collection('users')
          .where('userId', isEqualTo: uid)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) return q.docs.first.reference;
    }

    // 3) Fallback: query by email
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

  Future<void> _resetExpiryDate(UserModel user) async {
    final now = DateTime.now();
    final initial = user.accountExpiry ?? now.add(const Duration(days: 30));

    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Expiry Date'),
        content: Text(
          'Set expiry date for "${user.name ?? 'this user'}" to:\n\n'
          '${user.formatDate(picked)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final ref = await _resolveUserDocRef(user);
      if (ref == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to find user document to update expiry'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Store as Firestore Timestamp (recommended for DateTime)
      await ref.update({
        'accountExpiry': Timestamp.fromDate(
          DateTime(picked.year, picked.month, picked.day),
        ),
        'updatedAt': DateTime.now(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Expiry date updated'),
          backgroundColor: Colors.green,
        ),
      );
      await _fetchUsers();
    } catch (e) {
      debugPrint('Error updating expiry date: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating expiry date: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _confirmAndClearActiveDevice(UserModel user) async {
    final activeDevice = (user.activeDevice ?? '').trim();
    if (activeDevice.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Active Device'),
        content: Text(
          'Are you sure you want to clear the active device for "${user.name ?? 'this user'}"?\n\n'
          'Current device: $activeDevice',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final ref = await _resolveUserDocRef(user);
      if (ref == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to find user document to clear device'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      await ref.update({
        'activeDevice': FieldValue.delete(),
        'updatedAt': DateTime.now(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Active device cleared'),
          backgroundColor: Colors.green,
        ),
      );
      await _fetchUsers();
    } catch (e) {
      debugPrint('Error clearing active device: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error clearing active device: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
