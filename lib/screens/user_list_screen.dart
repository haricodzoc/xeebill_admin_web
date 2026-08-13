import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:xeebill_web/screens/settings_screen.dart';
import 'package:xeebill_web/utils/app_colors.dart';
import '../models/user_model.dart';
import 'bills_screen.dart';
import 'categories_screen.dart';
import 'items_screen.dart';
import 'revenue_summary_screen.dart';
import 'sub_profiles_screen.dart';
import 'reports_screen.dart';
import 'credit_payments_screen.dart';
import 'user_locations_screen.dart';
import 'user_customers_screen.dart';
import 'services_screen.dart';
import 'user_payment_history_screen.dart';

class UserListScreen extends StatefulWidget {
  const UserListScreen({super.key});

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isLoading = true;
  String? _errorMessage;
  List<UserModel> _users = [];
  bool _isAdmin = false;
  bool _isCheckingAdmin = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Map<String, String> _rechargePlanTitlesById = {};
  final Map<String, Future<UserLocationsBootstrap>> _locationsBootstrapFutures =
      {};
  final Set<String> _expandedUserKeys = {};

  static const String _kDefaultLabelSize = '38mm * 25mm';
  static const num _kDefaultRechargeAmount = 500;

  String _userCacheKey(UserModel user) {
    final doc = user.docId?.trim();
    if (doc != null && doc.isNotEmpty) return doc;
    final uid = user.userId?.trim();
    if (uid != null && uid.isNotEmpty) return uid;
    return user.email?.trim() ?? 'unknown';
  }

  String? _normalizePlanId(dynamic value, {bool allowEmpty = false}) {
    if (value == null) return null;
    var s = value.toString().trim();
    if (s.isEmpty) return allowEmpty ? '' : null;
    if ((s.startsWith('"') && s.endsWith('"')) ||
        (s.startsWith("'") && s.endsWith("'"))) {
      s = s.substring(1, s.length - 1).trim();
    }
    if (s.isEmpty) return allowEmpty ? '' : null;
    if (s.toLowerCase() == 'null') return null;
    return s;
  }

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
              'Access denied. Admin role required to view users.';
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
      final usersFuture = _firestore.collection('users').get();
      final plansFuture = _firestore.collection('recharge_plans').get();
      final results = await Future.wait([usersFuture, plansFuture]);
      final QuerySnapshot snapshot = results[0] as QuerySnapshot;
      final QuerySnapshot plansSnapshot = results[1] as QuerySnapshot;

      debugPrint('Found ${snapshot.docs.length} users');
      debugPrint('Found ${plansSnapshot.docs.length} recharge plans');

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

      final Map<String, String> plansById = {};
      for (final doc in plansSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        final planId = _normalizePlanId(data?['plan_id'], allowEmpty: true);
        final title = (data?['title'] ?? '').toString().trim();
        if (planId == null) continue;
        plansById[planId] = title.isEmpty ? planId : title;
      }

      // Sort users by name for better UX
      users.sort((a, b) {
        final nameA = a.name ?? '';
        final nameB = b.name ?? '';
        return nameA.compareTo(nameB);
      });

      setState(() {
        _users = users;
        _rechargePlanTitlesById = plansById;
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
      final phone = (u.phone ?? '').toLowerCase();
      final docId = (u.docId ?? '').toLowerCase();
      return name.contains(query) ||
          email.contains(query) ||
          phone.contains(query) ||
          docId.contains(query);
    }).toList();
  }

  String _initials(String? name) {
    final parts = (name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) {
      final s = parts.first;
      return s.substring(0, s.length >= 2 ? 2 : 1).toUpperCase();
    }
    return ('${parts.first[0]}${parts.last[0]}').toUpperCase();
  }

  Color _accountStatusColor({
    required bool isExpired,
    required bool isExpiringSoon,
  }) {
    if (isExpired) return AppColors.primaryRed;
    if (isExpiringSoon) return const Color(0xFFC27803);
    return AppColors.successGreen;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.primaryText,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Users',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            if (!_isLoading && _users.isNotEmpty)
              Text(
                '${_filteredUsers.length} user${_filteredUsers.length == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[600],
                ),
              ),
          ],
        ),
        actions: [
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh',
              onPressed: _checkAdminAndFetchUsers,
            ),
          if (_isAdmin)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: _showCreateCustomerDialog,
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: const Text('Create'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryGreen,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: _showCreateCustomerDialog,
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              elevation: 2,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Create Customer'),
            )
          : null,
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppColors.primaryGreen),
                  if (_isCheckingAdmin) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Checking admin access…',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
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
                    Icon(
                      Icons.error_outline_rounded,
                      size: 48,
                      color: AppColors.primaryRed.withValues(alpha: 0.85),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.grey[700]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    if (!_isAdmin)
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryGreen,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Go Back'),
                      )
                    else
                      ElevatedButton(
                        onPressed: _checkAdminAndFetchUsers,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryGreen,
                          foregroundColor: Colors.white,
                        ),
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
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreen.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.people_outline,
                      size: 36,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No users found',
                    style: TextStyle(
                      color: AppColors.primaryText,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              color: AppColors.primaryGreen,
              onRefresh: _fetchUsers,
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search by name, email, phone, or doc id',
                            hintStyle: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 14,
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: Colors.grey[500],
                            ),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded),
                                    onPressed: () {
                                      setState(() {
                                        _searchQuery = '';
                                        _searchController.clear();
                                      });
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: const Color(0xFFF5F7F9),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                color: Color(0xFFE8ECF0),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: AppColors.primaryGreen,
                                width: 1.2,
                              ),
                            ),
                            isDense: true,
                          ),
                          onChanged: (value) {
                            setState(() => _searchQuery = value);
                          },
                        ),
                        const SizedBox(height: 12),
                        Builder(
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
                            final expiringSoonCount =
                                _filteredUsers.where((u) {
                              final expiry = u.accountExpiry;
                              if (expiry == null) return false;
                              return !expiry.isBefore(now) &&
                                  expiry.isBefore(soonThreshold);
                            }).length;

                            return Row(
                              children: [
                                Expanded(
                                  child: _buildSummaryItem(
                                    'Total',
                                    _filteredUsers.length.toString(),
                                    Icons.people_outline,
                                    AppColors.primaryGreen,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _buildSummaryItem(
                                    'Expiring < 7d',
                                    expiringSoonCount.toString(),
                                    Icons.schedule_rounded,
                                    const Color(0xFFC27803),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _buildSummaryItem(
                                    'Expired',
                                    expiredCount.toString(),
                                    Icons.warning_amber_rounded,
                                    AppColors.primaryRed,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  Container(height: 1, color: const Color(0xFFE8ECF0)),
                  Expanded(
                    child: _filteredUsers.isEmpty
                        ? Center(
                            child: Text(
                              'No users match your search',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          )
                        : ListView.builder(
                            padding: EdgeInsets.fromLTRB(
                              16,
                              14,
                              16,
                              _isAdmin ? 96 : 24,
                            ),
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
    final isPremiumCustomer = user.isPremiumCustomer == true;
    final planId = _normalizePlanId(user.planId, allowEmpty: true);
    final activePlanName = planId == null
        ? 'Free'
        : (_rechargePlanTitlesById[planId] ??
              (planId.isEmpty ? 'Free' : 'Unknown Plan ($planId)'));
    final statusColor = _accountStatusColor(
      isExpired: isExpired,
      isExpiringSoon: isExpiringSoon,
    );
    final statusLabel = isExpired
        ? 'Expired'
        : isExpiringSoon
            ? 'Expiring soon'
            : 'Active';

    final key = _userCacheKey(user);
    final isExpanded = _expandedUserKeys.contains(key);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6E9ED)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 4,
            child: ColoredBox(color: statusColor),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    if (isExpanded) {
                      _expandedUserKeys.remove(key);
                    } else {
                      _expandedUserKeys.add(key);
                      _locationsBootstrapFutures.putIfAbsent(key, () async {
                        final ref = await _resolveUserDocRef(user);
                        if (ref == null) {
                          throw Exception('User document not found');
                        }
                        return loadUserLocationsBootstrap(ref);
                      });
                    }
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: statusColor.withValues(alpha: 0.12),
                        child: Text(
                          _initials(user.name),
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.name ?? 'Unknown',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: Color(0xFF1F2933),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [
                                if ((user.email ?? '').isNotEmpty) user.email!,
                                if ((user.phone ?? '').isNotEmpty) user.phone!,
                              ].join('  ·  '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 12.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _metaChip(
                                  icon: Icons.event_outlined,
                                  label: '$statusLabel · $expiryText',
                                  color: statusColor,
                                ),
                                _metaChip(
                                  icon: Icons.workspace_premium_outlined,
                                  label: activePlanName,
                                  color: AppColors.primaryGreen,
                                ),
                                if (user.role != null)
                                  _metaChip(
                                    icon: Icons.badge_outlined,
                                    label: user.role!,
                                    color: user.role == 'ADMIN'
                                        ? AppColors.primaryGreen
                                        : AppColors.primaryGrey,
                                  ),
                                if (isPremiumCustomer)
                                  _metaChip(
                                    icon: Icons.star_rounded,
                                    label: 'Premium',
                                    color: const Color(0xFFB45309),
                                  ),
                                if (hasActiveDevice)
                                  _metaChip(
                                    icon: Icons.devices_outlined,
                                    label: 'Device linked',
                                    color: AppColors.primaryGrey,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        isExpanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: Colors.grey[500],
                      ),
                    ],
                  ),
                ),
              ),
              if (isExpanded)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 0, 12, 14),
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE8ECF0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ACCOUNT DETAILS',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 0.7,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildInfoRow('Doc ID', user.docId ?? 'N/A'),
                      _buildInfoRow('User ID', user.userId ?? 'N/A'),
                      _buildInfoRow('Phone', user.phone ?? 'N/A'),
                      _buildInfoRow('Address', user.address ?? 'N/A'),
                      _buildInfoRow('GST Number', user.gstNumber ?? 'N/A'),
                      _buildActivePlanRow(user, activePlanName),
                      _buildPremiumCustomerRow(user),
                      _buildActiveDeviceRow(user),
                      _buildAccountExpiryRow(user),
                      _buildInfoRow(
                        'Created At',
                        user.formatDate(user.createdAt),
                      ),
                      _buildInfoRow(
                        'Updated At',
                        user.formatDate(user.updatedAt),
                      ),
                      _buildInfoRow(
                        'Last Login',
                        user.formatDate(user.lastLogin),
                      ),
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
                      const SizedBox(height: 16),
                      Text(
                        'QUICK ACTIONS',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 0.7,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildActionButton(
                            'View Bills',
                            Icons.receipt_long_outlined,
                            AppColors.primaryGreen,
                            () => _navigateToBills(context, user),
                          ),
                          _buildActionButton(
                            'Customers',
                            Icons.groups_2_outlined,
                            AppColors.primaryGreen,
                            () => _navigateToCustomers(context, user),
                          ),
                          _buildActionButton(
                            'Categories',
                            Icons.category_outlined,
                            AppColors.primaryGreen,
                            () => _navigateToCategories(context, user),
                          ),
                          _buildActionButton(
                            'Items',
                            Icons.inventory_2_outlined,
                            AppColors.primaryGreen,
                            () => _navigateToItems(context, user),
                          ),
                          _buildActionButton(
                            'Services',
                            Icons.build_circle_outlined,
                            AppColors.primaryGreen,
                            () => _navigateToServices(context, user),
                          ),
                          _buildActionButton(
                            'Revenue Summary',
                            Icons.insights_outlined,
                            AppColors.primaryGreen,
                            () => _navigateToRevenueSummary(context, user),
                          ),
                          _buildActionButton(
                            'Sub Profiles',
                            Icons.people_outline,
                            AppColors.primaryGreen,
                            () => _navigateToSubProfiles(context, user),
                          ),
                          _buildActionButton(
                            'Locations',
                            Icons.location_on_outlined,
                            AppColors.primaryGreen,
                            () => _openUserLocations(context, user),
                          ),
                          _buildActionButton(
                            'Reports',
                            Icons.analytics_outlined,
                            AppColors.primaryGreen,
                            () => _navigateToReports(context, user),
                          ),
                          _buildActionButton(
                            'Credit & Payments',
                            Icons.payment_outlined,
                            AppColors.primaryGreen,
                            () => _navigateToCreditPayments(context, user),
                          ),
                          _buildActionButton(
                            'Payment History',
                            Icons.history_rounded,
                            AppColors.primaryGreen,
                            () => _navigateToPaymentHistory(context, user),
                          ),
                          _buildActionButton(
                            'Settings',
                            Icons.settings_outlined,
                            AppColors.primaryGrey,
                            () => _navigateToSettings(context, user),
                          ),
                          _buildActionButton(
                            'Custom Template',
                            Icons.code_rounded,
                            AppColors.primaryGrey,
                            () => _showCustomTemplateDialog(user),
                          ),
                          _buildActionButton(
                            'Additional Settings',
                            Icons.tune_rounded,
                            AppColors.primaryGrey,
                            () => _showAdditionalSettingsDialog(user),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metaChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.28)),
        backgroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
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

  void _navigateToCustomers(BuildContext context, UserModel user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserCustomersScreen(user: user),
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

  void _navigateToServices(BuildContext context, UserModel user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ServicesScreen(userId: user.userId ?? ''),
      ),
    );
  }

  void _navigateToRevenueSummary(BuildContext context, UserModel user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RevenueSummaryScreen(userId: user.userId ?? ''),
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

  Future<void> _openUserLocations(BuildContext context, UserModel user) async {
    final key = _userCacheKey(user);
    try {
      final ref = await _resolveUserDocRef(user);
      if (ref == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to find user document'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      Future<UserLocationsBootstrap> fut;
      if (_locationsBootstrapFutures.containsKey(key)) {
        fut = _locationsBootstrapFutures[key]!;
      } else {
        fut = loadUserLocationsBootstrap(ref);
        _locationsBootstrapFutures[key] = fut;
      }
      final bootstrap = await fut;

      if (!context.mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (context) => UserLocationsScreen(
            userRef: ref,
            displayName: user.name ?? user.email ?? 'User',
            initialBootstrap: bootstrap,
          ),
        ),
      );
      _locationsBootstrapFutures.remove(key);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not load locations: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
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

  void _navigateToPaymentHistory(BuildContext context, UserModel user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserPaymentHistoryScreen(user: user),
      ),
    );
  }

  void _navigateToSettings(BuildContext context, UserModel user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          userId: user.userId,
          userDocId: user.docId,
          userName: user.name,
        ),
      ),
    );
  }

  int _parseAdditionalSettingValue(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  String _customTemplateToEditorText(dynamic raw) {
    if (raw == null) {
      return const JsonEncoder.withIndent('  ').convert({
        'labelSize': '75mm * 50mm',
        'values': <String, dynamic>{},
        'elements': <dynamic>[],
      });
    }
    try {
      if (raw is Map) {
        return const JsonEncoder.withIndent('  ').convert(raw);
      }
      // Migrate the previous admin format, which stored one template in a list.
      if (raw is List && raw.length == 1 && raw.first is Map) {
        return const JsonEncoder.withIndent('  ').convert(raw.first);
      }
    } catch (_) {}
    return const JsonEncoder.withIndent('  ').convert({
      'labelSize': '75mm * 50mm',
      'values': <String, dynamic>{},
      'elements': <dynamic>[],
    });
  }

  Map<String, dynamic>? _parseCustomTemplateJson(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    final decoded = jsonDecode(trimmed);
    dynamic template = decoded;
    // Accept and migrate the old one-item array shape.
    if (decoded is List && decoded.length == 1) {
      template = decoded.first;
    }
    if (template is! Map) return null;
    return Map<String, dynamic>.from(template);
  }

  Future<void> _showCustomTemplateDialog(UserModel user) async {
    final ref = await _resolveUserDocRef(user);
    if (ref == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to find user document to update custom template'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final settingsSnap = await ref.collection('settings').doc('app').get();
    final settingsData = settingsSnap.data() ?? <String, dynamic>{};
    final templateController = TextEditingController(
      text: _customTemplateToEditorText(settingsData['custom_template']),
    );
    String? validationError;
    bool isSaving = false;

    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> save() async {
              Map<String, dynamic>? parsed;
              try {
                parsed = _parseCustomTemplateJson(templateController.text);
              } catch (e) {
                setDialogState(() {
                  validationError = 'Invalid JSON: $e';
                });
                return;
              }

              if (parsed == null) {
                setDialogState(() {
                  validationError =
                      'Custom template must be one JSON object.';
                });
                return;
              }

              if (parsed['elements'] is! List) {
                setDialogState(() {
                  validationError =
                      'Custom template must contain an "elements" array.';
                });
                return;
              }

              setDialogState(() {
                validationError = null;
                isSaving = true;
              });

              try {
                await ref
                    .collection('settings')
                    .doc('app')
                    .set({
                  'custom_template': parsed,
                }, SetOptions(merge: true));

                if (Navigator.of(dialogContext).canPop()) {
                  Navigator.of(dialogContext).pop(true);
                }
              } catch (e) {
                setDialogState(() {
                  isSaving = false;
                  validationError = 'Failed to save: $e';
                });
              }
            }

            return AlertDialog(
              title: Text(
                'Custom Template - ${user.name ?? 'User'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              content: SizedBox(
                width: 640,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Edit one custom label template JSON object. It must contain an "elements" array.',
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: templateController,
                        maxLines: 18,
                        minLines: 12,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Custom template JSON',
                          hintText: '{\n  "labelSize": "75mm * 50mm",\n  "values": {},\n  "elements": []\n}',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                      if (validationError != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          validationError!,
                          style: const TextStyle(color: Colors.red, fontSize: 13),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving ? null : save,
                  child: isSaving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    templateController.dispose();

    if (updated == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Custom template saved successfully'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _showAdditionalSettingsDialog(UserModel user) async {
    final ref = await _resolveUserDocRef(user);
    if (ref == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to find user document to update settings'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final snap = await ref.get();
    final data = snap.data() ?? <String, dynamic>{};

    final devicesController = TextEditingController(
      text: _parseAdditionalSettingValue(
        data['additional_devices_allowed'],
      ).toString(),
    );
    final itemsController = TextEditingController(
      text: _parseAdditionalSettingValue(
        data['additional_items_allowed'],
      ).toString(),
    );
    final customersController = TextEditingController(
      text: _parseAdditionalSettingValue(
        data['additional_customers_allowed'],
      ).toString(),
    );
    final billsController = TextEditingController(
      text: _parseAdditionalSettingValue(
        data['additional_bills_allowed'],
      ).toString(),
    );

    bool isSaving = false;

    final updated = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> save() async {
              final devices = int.tryParse(devicesController.text.trim());
              final items = int.tryParse(itemsController.text.trim());
              final customers = int.tryParse(customersController.text.trim());
              final bills = int.tryParse(billsController.text.trim());

              if ([devices, items, customers, bills].any((v) => v == null)) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('All values must be valid numbers'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              if ([devices!, items!, customers!, bills!].any((v) => v < 0)) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Values cannot be negative'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }

              setDialogState(() => isSaving = true);
              try {
                await ref.update({
                  'additional_devices_allowed': devices,
                  'additional_items_allowed': items,
                  'additional_customers_allowed': customers,
                  'additional_bills_allowed': bills,
                  'updatedAt': DateTime.now(),
                });
                if (Navigator.of(dialogContext).canPop()) {
                  Navigator.of(dialogContext).pop(true);
                }
              } catch (e) {
                setDialogState(() => isSaving = false);
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text('Failed to update settings: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }

            Widget buildNumberField(String label, TextEditingController c) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  controller: c,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: label,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              );
            }

            return AlertDialog(
              title: Text(
                'Additional Settings - ${user.name ?? 'User'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      buildNumberField(
                        'Additional Devices Allowed',
                        devicesController,
                      ),
                      buildNumberField(
                        'Additional Items Allowed',
                        itemsController,
                      ),
                      buildNumberField(
                        'Additional Users Allowed',
                        customersController,
                      ),
                      buildNumberField(
                        'Additional Bills Allowed',
                        billsController,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving ? null : save,
                  child: isSaving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Update'),
                ),
              ],
            );
          },
        );
      },
    );

    devicesController.dispose();
    itemsController.dispose();
    customersController.dispose();
    billsController.dispose();

    if (updated == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Additional settings updated successfully'),
          backgroundColor: Colors.green,
        ),
      );
      await _fetchUsers();
    }
  }

  Widget _buildSummaryItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: color,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateCustomerDialog() async {
    final formKey = GlobalKey<FormState>();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final gstNumberController = TextEditingController();
    final phoneController = TextEditingController();
    var gstType = 'Regular';
    var isPremiumCustomer = false;
    var isSubmitting = false;

    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (!(formKey.currentState?.validate() ?? false)) return;

              setDialogState(() => isSubmitting = true);
              final success = await _createCustomerWithAuth(
                email: emailController.text.trim(),
                password: passwordController.text,
                name: nameController.text.trim(),
                address: addressController.text.trim(),
                gstType: gstType,
                gstNumber: gstNumberController.text.trim().toUpperCase(),
                phone: phoneController.text.trim(),
                isPremiumCustomer: isPremiumCustomer,
              );
              if (!mounted) return;
              if (success) {
                Navigator.of(this.context).pop(true);
              } else {
                setDialogState(() => isSubmitting = false);
              }
            }

            return AlertDialog(
              title: const Text('Create Customer'),
              content: SizedBox(
                width: 520,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(labelText: 'Email'),
                          validator: (v) {
                            final value = (v ?? '').trim();
                            if (value.isEmpty) return 'Email is required';
                            final emailRegex = RegExp(
                              r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
                            );
                            if (!emailRegex.hasMatch(value)) {
                              return 'Enter a valid email';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                          ),
                          validator: (v) {
                            if ((v ?? '').length < 6) {
                              return 'Password must be at least 6 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: nameController,
                          maxLength: 25,
                          decoration: const InputDecoration(
                            labelText: 'Shop name',
                            counterText: '',
                          ),
                          validator: (v) {
                            if ((v ?? '').trim().isEmpty) {
                              return 'Shop name is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: addressController,
                          maxLength: 60,
                          decoration: const InputDecoration(
                            labelText: 'Shop address',
                            counterText: '',
                          ),
                          validator: (v) {
                            if ((v ?? '').trim().isEmpty) {
                              return 'Address is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: gstType,
                          decoration: const InputDecoration(
                            labelText: 'GST Type',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'Regular',
                              child: Text('Regular'),
                            ),
                            DropdownMenuItem(
                              value: 'Composition',
                              child: Text('Composition'),
                            ),
                            DropdownMenuItem(
                              value: 'Unregistered',
                              child: Text('Unregistered'),
                            ),
                          ],
                          onChanged: isSubmitting
                              ? null
                              : (v) {
                                  if (v == null) return;
                                  setDialogState(() => gstType = v);
                                },
                        ),
                        if (gstType != 'Unregistered') ...[
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: gstNumberController,
                            textCapitalization: TextCapitalization.characters,
                            maxLength: 15,
                            decoration: const InputDecoration(
                              labelText: 'GST Number',
                              counterText: '',
                            ),
                            validator: (v) {
                              if (gstType == 'Unregistered') return null;
                              if ((v ?? '').trim().isEmpty) {
                                return 'GST Number is required';
                              }
                              return null;
                            },
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          maxLength: 10,
                          decoration: const InputDecoration(
                            labelText: 'Phone Number',
                            counterText: '',
                          ),
                          validator: (v) {
                            if ((v ?? '').trim().isEmpty) {
                              return 'Phone number is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile.adaptive(
                          value: isPremiumCustomer,
                          onChanged: isSubmitting
                              ? null
                              : (v) => setDialogState(
                                  () => isPremiumCustomer = v,
                                ),
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Premium customer'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: isSubmitting ? null : submit,
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.person_add),
                  label: Text(isSubmitting ? 'Creating...' : 'Create'),
                ),
              ],
            );
          },
        );
      },
    );

    emailController.dispose();
    passwordController.dispose();
    nameController.dispose();
    addressController.dispose();
    gstNumberController.dispose();
    phoneController.dispose();

    if (created == true) {
      await _fetchUsers();
    }
  }

  Future<bool> _createCustomerWithAuth({
    required String email,
    required String password,
    required String name,
    required String address,
    required String gstType,
    required String gstNumber,
    required String phone,
    required bool isPremiumCustomer,
  }) async {
    FirebaseApp? tempApp;
    try {
      final existingByEmail = await _firestore
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (existingByEmail.docs.isNotEmpty) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User with this email already exists'),
            backgroundColor: Colors.red,
          ),
        );
        return false;
      }

      final appName = 'create-user-${DateTime.now().millisecondsSinceEpoch}';
      tempApp = await Firebase.initializeApp(
        name: appName,
        options: Firebase.app().options,
      );
      final tempAuth = FirebaseAuth.instanceFor(app: tempApp);
      final cred = await tempAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final newUid = cred.user?.uid;
      if (newUid == null) {
        throw FirebaseAuthException(
          code: 'unknown',
          message: 'Failed to create auth user',
        );
      }

      final userRef = _firestore.collection('users').doc(newUid);
      final appSettingsRef = userRef.collection('settings').doc('app');
      final subProfilesRef = userRef.collection('subProfiles');

      final now = FieldValue.serverTimestamp();
      final randomPin = (100000 + DateTime.now().millisecond * 37) % 900000;
      final pin = (100000 + randomPin).toString().padLeft(6, '0');

      await userRef.set({
        'email': email,
        'name': name,
        'address': address,
        'gstNumber': gstNumber,
        'userId': newUid,
        'phone': phone,
        'activeDevice': null,
        'role': 'ADMIN',
        'uploadErrorLog': false,
        'resetSyncTime': false,
        'item_version': 1,
        'bill_version': 1,
        'planId': null,
        'last_bill_archived_time': null,
        'accountExpiry': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 30)),
        ),
        'is_premium_account': isPremiumCustomer,
        'createdAt': now,
        'updatedAt': now,
        'lastLogin': now,
      });

      await appSettingsRef.set({
        'gstType': gstType,
        'labelSize': _kDefaultLabelSize,
        'enableHsn': false,
        'showTaxOnBill': gstType == 'Regular',
        'flashOnScan': true,
        'voiceBillingEnabled': true,
        'applyRoundOff': false,
        'rechargeAmount': _kDefaultRechargeAmount,
        'adminMode': true,
        'taxToggle': true,
        'createdAt': now,
        'updatedAt': now,
      });

      await subProfilesRef.add({
        'prefix': '2',
        'name': 'Super Admin',
        'code': 'SA',
        'avatar': 'assets/images/avatar1.svg',
        'pin': pin,
        'status': 'inactive',
        'lastSyncTime': null,
        'itemSyncTime': null,
        'categorySyncTime': null,
        'billSyncTime': null,
        'itemMappingSyncTime': null,
        'discountSyncTime': null,
        'updatedAt': now,
        'permissions': {
          'Bills': true,
          'Button': false,
          'Categories': true,
          'Credits & Payments': true,
          'Discounts': true,
          'Items': true,
          'Reports': true,
          'Service History': true,
        },
        'itemsOptions': {
          'View items': true,
          'Add items': true,
          'Edit items': true,
          'Delete items': true,
          'Map items': true,
          'Print label': true,
        },
        'categoriesOptions': {
          'Add categories': true,
          'Edit categories': true,
          'Delete categories': true,
        },
        'reportsOptions': {
          'View sales report': true,
          'View invoice report': true,
          'View inventory report': true,
        },
      });

      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Customer created successfully'),
          backgroundColor: Colors.green,
        ),
      );
      return true;
    } on FirebaseAuthException catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Failed to create user'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating customer: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    } finally {
      if (tempApp != null) {
        await tempApp.delete();
      }
    }
  }

  Widget _buildInfoRow(String label, String value, [Color? valueColor]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? AppColors.primaryText,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivePlanRow(UserModel user, String activePlanName) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              'Active Plan:',
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
                    activePlanName,
                    style: TextStyle(
                      color: AppColors.primaryText,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _showSetActivePlanDialog(user),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    foregroundColor: AppColors.primaryGreen,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Set Plan'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSetActivePlanDialog(UserModel user) async {
    final currentPlanId = _normalizePlanId(user.planId, allowEmpty: true);

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
          future: _firestore.collection('recharge_plans').get(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const AlertDialog(
                title: Text('Set Active Plan'),
                content: SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }

            if (snapshot.hasError) {
              return AlertDialog(
                title: const Text('Set Active Plan'),
                content: Text('Failed to load plans: ${snapshot.error}'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Close'),
                  ),
                ],
              );
            }

            final docs = snapshot.data?.docs ?? [];
            final plans = docs.map((doc) {
              final data = doc.data();
              return (
                docId: doc.id,
                planId: _normalizePlanId(data['plan_id'], allowEmpty: true) ??
                    '',
                title: (data['title'] ?? '').toString().trim(),
                subtitle: (data['subtitle'] ?? '').toString().trim(),
                price: (data['price'] as num?)?.toDouble() ?? 0,
                durationInDays: (data['duration_in_days'] as num?)?.toInt() ?? 0,
              );
            }).where((p) => p.planId.isNotEmpty).toList()
              ..sort((a, b) {
                final byTitle = a.title.compareTo(b.title);
                if (byTitle != 0) return byTitle;
                return a.planId.compareTo(b.planId);
              });

            return AlertDialog(
              title: Text(
                'Set Active Plan — ${user.name ?? user.email ?? 'User'}',
              ),
              content: SizedBox(
                width: 480,
                child: plans.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text('No plans found in recharge_plans.'),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: plans.length + 1,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            final isSelected =
                                currentPlanId == null || currentPlanId.isEmpty;
                            return ListTile(
                              leading: Icon(
                                isSelected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                color: AppColors.primaryGreen,
                              ),
                              title: const Text('Free / No plan'),
                              subtitle: const Text('Clears planId on this user'),
                              onTap: () async {
                                Navigator.pop(dialogContext);
                                await _setUserPlanId(user, null);
                              },
                            );
                          }

                          final plan = plans[index - 1];
                          final isSelected = currentPlanId == plan.planId;
                          final title = plan.title.isEmpty
                              ? plan.planId
                              : plan.title;
                          final details = <String>[
                            'ID: ${plan.planId}',
                            if (plan.durationInDays > 0)
                              '${plan.durationInDays} days',
                            '₹${plan.price.toStringAsFixed(plan.price % 1 == 0 ? 0 : 2)}',
                          ].join(' · ');

                          return ListTile(
                            leading: Icon(
                              isSelected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: AppColors.primaryGreen,
                            ),
                            title: Text(
                              title,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              [
                                if (plan.subtitle.isNotEmpty) plan.subtitle,
                                details,
                              ].where((s) => s.isNotEmpty).join('\n'),
                            ),
                            isThreeLine: plan.subtitle.isNotEmpty,
                            onTap: () async {
                              Navigator.pop(dialogContext);
                              await _setUserPlanId(user, plan.planId);
                            },
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _setUserPlanId(UserModel user, String? planId) async {
    try {
      final ref = await _resolveUserDocRef(user);
      if (ref == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to find user document to update'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final normalized = _normalizePlanId(planId, allowEmpty: true);
      await ref.update({
        'planId': (normalized == null || normalized.isEmpty) ? null : normalized,
        'updatedAt': DateTime.now(),
      });

      if (!mounted) return;
      final label = (normalized == null || normalized.isEmpty)
          ? 'Free / No plan'
          : (_rechargePlanTitlesById[normalized] ?? normalized);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Active plan set to $label'),
          backgroundColor: Colors.green,
        ),
      );
      await _fetchUsers();
    } catch (e) {
      debugPrint('Error updating planId: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating active plan: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildPremiumCustomerRow(UserModel user) {
    final isPremium = user.isPremiumCustomer == true;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              'Premium customer:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isPremium ? 'Yes' : 'No',
                    style: TextStyle(
                      color: isPremium ? Colors.amber[900] : Colors.black87,
                      fontSize: 13,
                      fontWeight:
                          isPremium ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: isPremium,
                  onChanged: (v) => _setPremiumCustomer(user, v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setPremiumCustomer(UserModel user, bool value) async {
    try {
      final ref = await _resolveUserDocRef(user);
      if (ref == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to find user document to update'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      await ref.update({
        'is_premium_account': value,
        'updatedAt': DateTime.now(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Marked as premium customer'
                : 'Premium customer flag cleared',
          ),
          backgroundColor: Colors.green,
        ),
      );
      await _fetchUsers();
    } catch (e) {
      debugPrint('Error updating is_premium_account: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating premium flag: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
                    child: const Text('Clear Active Device'),
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
                  child: const Text('Reset Account Expiry'),
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
    // 0) Prefer the document id from the list we loaded (most reliable)
    final listedDocId = user.docId?.trim();
    if (listedDocId != null && listedDocId.isNotEmpty) {
      final ref = _firestore.collection('users').doc(listedDocId);
      final snap = await ref.get();
      if (snap.exists) return ref;
    }

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
    if (!mounted) return;

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
