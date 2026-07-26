import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/sub_profile_model.dart';
import '../utils/app_colors.dart';
import '../utils/constants.dart';
import '../utils/functions.dart';

class SubProfilesScreen extends StatefulWidget {
  final String userId;

  const SubProfilesScreen({super.key, required this.userId});

  @override
  State<SubProfilesScreen> createState() => _SubProfilesScreenState();
}

class _SubProfilesScreenState extends State<SubProfilesScreen> {
  final TextEditingController _profileNameController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  List<SubProfileModel> _subProfiles = [];
  bool _isLoading = false;
  bool _isCreating = false;
  String? _activatingProfileId;
  bool _hasExistingBills = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkExistingBills();
      await _loadSubProfiles();
    });
  }

  @override
  void dispose() {
    _profileNameController.dispose();
    super.dispose();
  }

  Future<void> _checkExistingBills() async {
    try {
      final user = _auth.currentUser;
      final userId = widget.userId.isNotEmpty ? widget.userId : user?.uid;
      if (userId == null || userId.isEmpty) return;

      final billsSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('bills')
          .limit(1)
          .get();

      setState(() {
        _hasExistingBills = billsSnapshot.docs.isNotEmpty;
      });
    } catch (e) {
      await logErrorToFile(e.toString(), StackTrace.current);
      debugPrint('Error checking existing bills: $e');
    }
  }

  Future<void> _loadSubProfiles() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = _auth.currentUser;
      final userId = widget.userId.isNotEmpty ? widget.userId : user?.uid;
      debugPrint('userId: $userId');
      if (userId == null || userId.isEmpty) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Try with orderBy first, if it fails, try without
      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('subProfiles')
          .orderBy('updatedAt', descending: true)
          .get();

      final profiles = <SubProfileModel>[];
      for (final doc in snapshot.docs) {
        try {
          final profile = SubProfileModel.fromMap(
            doc.data() as Map<String, dynamic>,
            doc.id,
          );
          profiles.add(profile);
        } catch (e) {
          debugPrint('Error parsing profile ${doc.id}: $e');
          logErrorToFile(
            'Error parsing profile ${doc.id}: $e',
            StackTrace.current,
          );
        }
      }

      // Sort manually if orderBy didn't work
      profiles.sort((a, b) {
        final aTime = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });

      debugPrint('Loaded ${profiles.length} sub profiles');
      setState(() {
        _subProfiles = profiles;
        _isLoading = false;
      });
    } catch (e) {
      await logErrorToFile(e.toString(), StackTrace.current);
      debugPrint('Error loading sub profiles: $e');
      if (mounted) {
        showSnackbar(
          context,
          'Error loading sub profiles: $e',
          backgroundColor: Colors.red,
        );
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _createSubProfile() async {
    if (_profileNameController.text.trim().isEmpty) {
      showSnackbar(
        context,
        'Please enter a profile name',
        backgroundColor: Colors.orange,
      );
      return;
    }

    final profileName = _profileNameController.text.trim();
    if (profileName.length > 12) {
      showSnackbar(
        context,
        'Profile name must be 12 characters or less',
        backgroundColor: Colors.orange,
      );
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      final user = _auth.currentUser;
      final userId = widget.userId.isNotEmpty ? widget.userId : user?.uid;

      if (userId == null || userId.isEmpty) {
        showSnackbar(
          context,
          'User not authenticated',
          backgroundColor: Colors.red,
        );
        setState(() {
          _isCreating = false;
        });
        return;
      }

      // Generate a unique code (2-3 characters)
      final existingCodes = _subProfiles.map((p) => p.code).toSet();
      String code;
      do {
        code = _generateProfileCode();
      } while (existingCodes.contains(code));

      // Get the next prefix number
      final nextPrefix = _subProfiles.isEmpty
          ? '1'
          : (_subProfiles.length + 1).toString();

      final profileData = {
        'prefix': nextPrefix,
        'name': profileName,
        'code': code,
        'avatar': 'default',
        'pin': '',
        'status': 'inactive',
        'createdAt': DateTime.now(),
        'updatedAt': DateTime.now(),
      };

      await _firestore
          .collection('users')
          .doc(userId)
          .collection('subProfiles')
          .add(profileData);

      _profileNameController.clear();
      await _loadSubProfiles();

      if (mounted) {
        showSnackbar(
          context,
          'Sub profile created successfully',
          backgroundColor: Colors.green,
        );
      }
    } catch (e) {
      await logErrorToFile(e.toString(), StackTrace.current);
      if (mounted) {
        showSnackbar(
          context,
          'Error creating sub profile: $e',
          backgroundColor: Colors.red,
        );
      }
    } finally {
      setState(() {
        _isCreating = false;
      });
    }
  }

  String _generateProfileCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final random = Random();
    return String.fromCharCodes(
      Iterable.generate(
        2,
        (_) => chars.codeUnitAt(random.nextInt(chars.length)),
      ),
    );
  }

  Future<void> _activateSubProfile(SubProfileModel profile) async {
    setState(() {
      _activatingProfileId = profile.id;
    });

    try {
      final user = _auth.currentUser;
      final userId = widget.userId.isNotEmpty ? widget.userId : user?.uid;

      if (userId == null || userId.isEmpty) {
        showSnackbar(
          context,
          'User not authenticated',
          backgroundColor: Colors.red,
        );
        setState(() {
          _activatingProfileId = null;
        });
        return;
      }

      // Deactivate all other profiles
      final batch = _firestore.batch();
      for (final p in _subProfiles) {
        if (p.id != profile.id) {
          final ref = _firestore
              .collection('users')
              .doc(userId)
              .collection('subProfiles')
              .doc(p.id);
          batch.update(ref, {
            'status': 'inactive',
            'updatedAt': DateTime.now(),
          });
        }
      }

      // Activate the selected profile
      final profileRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('subProfiles')
          .doc(profile.id);
      batch.update(profileRef, {
        'status': 'active',
        'updatedAt': DateTime.now(),
      });

      await batch.commit();

      // Update constants
      ACTIVE_PROFILE_ID = profile.id;
      ACTIVE_PROFILE_PREFIX = profile.prefix;
      ACTIVE_PROFILE_NAME = profile.name;
      ACTIVE_PROFILE_CODE = profile.code;
      IS_SUB_PROFILE = true;

      await _loadSubProfiles();

      if (mounted) {
        showSnackbar(
          context,
          'Profile activated successfully',
          backgroundColor: Colors.green,
        );
        Navigator.pop(context);
      }
    } catch (e) {
      await logErrorToFile(e.toString(), StackTrace.current);
      if (mounted) {
        showSnackbar(
          context,
          'Error activating profile: $e',
          backgroundColor: Colors.red,
        );
      }
    } finally {
      setState(() {
        _activatingProfileId = null;
      });
    }
  }

  Future<bool> _deleteSubProfile(String profileId) async {
    try {
      final user = _auth.currentUser;
      final userId = widget.userId.isNotEmpty ? widget.userId : user?.uid;
      if (userId == null || userId.isEmpty) return false;

      await _firestore
          .collection('users')
          .doc(userId)
          .collection('subProfiles')
          .doc(profileId)
          .delete();

      await _loadSubProfiles();
      return true;
    } catch (e) {
      await logErrorToFile(e.toString(), StackTrace.current);
      return false;
    }
  }

  bool _isProfileActivating(String profileId) {
    return _activatingProfileId == profileId;
  }

  Future<void> _updateSubProfileStatus(
    SubProfileModel profile,
    String newStatus,
  ) async {
    if (newStatus == profile.status) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update Status'),
        content: Text(
          'Do you want to change status to ${newStatus == 'active' ? 'Active' : 'Inactive'} for "${profile.name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
            ),
            child: const Text('Update'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final user = _auth.currentUser;
      final userId = widget.userId.isNotEmpty ? widget.userId : user?.uid;
      if (userId == null || userId.isEmpty) {
        showSnackbar(
          context,
          'User not authenticated',
          backgroundColor: Colors.red,
        );
        return;
      }

      if (newStatus == 'active') {
        await _activateSubProfile(profile);
      } else {
        await _firestore
            .collection('users')
            .doc(userId)
            .collection('subProfiles')
            .doc(profile.id)
            .update({'status': 'inactive', 'updatedAt': DateTime.now()});

        if (ACTIVE_PROFILE_ID == profile.id) {
          ACTIVE_PROFILE_ID = '';
          ACTIVE_PROFILE_PREFIX = '';
          ACTIVE_PROFILE_NAME = '';
          ACTIVE_PROFILE_CODE = '';
          IS_SUB_PROFILE = false;
        }

        await _loadSubProfiles();
        if (mounted) {
          showSnackbar(
            context,
            'Profile status updated to inactive',
            backgroundColor: Colors.green,
          );
        }
      }
    } catch (e) {
      await logErrorToFile(e.toString(), StackTrace.current);
      if (mounted) {
        showSnackbar(
          context,
          'Failed to update profile status: $e',
          backgroundColor: Colors.red,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.backgroundGrey,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            color: AppColors.primaryGreen,
            size: 18,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: const Text(
          'Sub Profiles',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: Container(
        color: AppColors.primaryWhite,
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              const SizedBox(height: 20),
              TextFormField(
                controller: _profileNameController,
                maxLines: 1,
                maxLength: 12,
                keyboardType: TextInputType.text,
                decoration: InputDecoration(
                  hintText: 'Profile name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: AppColors.activeGreen.withOpacity(0.18),
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 16,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isCreating ? null : _createSubProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _isCreating
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
                    : const Text(
                        'Add Sub Profile',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        itemCount: _subProfiles.length,
                        itemBuilder: (context, index) {
                          final profile = _subProfiles[index];
                          return Padding(
                            key: Key(profile.id),
                            padding: const EdgeInsets.only(top: 8.0),
                            child: GestureDetector(
                              onLongPress: () {
                                if (profile.status == 'active') {
                                  showSnackbar(
                                    context,
                                    'Cannot delete the active profile',
                                    backgroundColor: Colors.orange,
                                  );
                                  return;
                                }
                                _showDeleteConfirmation(context, profile).then((
                                  confirmed,
                                ) {
                                  if (confirmed == true) {
                                    final removedProfile = _subProfiles
                                        .removeAt(index);
                                    _deleteSubProfile(profile.id).then((
                                      success,
                                    ) {
                                      if (!success) {
                                        _subProfiles.insert(
                                          index,
                                          removedProfile,
                                        );
                                        if (mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Failed to delete ${profile.name}',
                                              ),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                        }
                                      } else {
                                        setState(() {});
                                      }
                                    });
                                  }
                                });
                              },
                              child: SubProfileCard(
                                userDocumentId: widget.userId,
                                profile: profile,
                                canActivate: false,
                                isActivating: _isProfileActivating(profile.id),
                                onActivate: () async {
                                  bool? confirmed =
                                      await _showActivateConfirmation(
                                        context,
                                        profile,
                                        _hasExistingBills,
                                      );
                                  if (confirmed == true) {
                                    await _activateSubProfile(profile);
                                  }
                                },
                                onStatusChanged: (newStatus) =>
                                    _updateSubProfileStatus(
                                      profile,
                                      newStatus,
                                    ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// Sub Profile Card Widget
class SubProfileCard extends StatefulWidget {
  final String userDocumentId;
  final SubProfileModel profile;
  final bool canActivate;
  final bool isActivating;
  final VoidCallback onActivate;
  final Future<void> Function(String newStatus)? onStatusChanged;

  const SubProfileCard({
    super.key,
    required this.userDocumentId,
    required this.profile,
    required this.canActivate,
    required this.isActivating,
    required this.onActivate,
    this.onStatusChanged,
  });

  @override
  State<SubProfileCard> createState() => _SubProfileCardState();
}

class _SubProfileCardState extends State<SubProfileCard> {
  bool isUpdatingPermission = false;
  bool isUpdatingSettings = false;
  bool _isUpdatingStatus = false;
  bool _permissionsExpanded = false;
  bool _settingsExpanded = false;

  bool _flashOnScan = false;
  bool _voiceBillingEnabled = false;
  bool _barcodeScanningEnabled = false;
  bool _repeatScanning = false;
  bool _externalScanner = false;
  bool _scannedItemConfirmation = false;
  bool _directItemAdditionEnabled = false;
  String _receiptSize = kDefaultReceiptSize;

  final Map<String, bool> _enabled = {
    'Bills': false,
    'Categories': false,
    'Items': false,
    'Reports': false,
    'Discounts': false,
    'Credits & Payments': false,
    'Dashboard': false,
    'Contacts': false,
    'Services': false,
    'Button': false,
  };
  final Map<String, bool> _itemsOptions = {
    'View items': false,
    'Add items': false,
    'Edit items': false,
    'Delete items': false,
    'Map items': false,
    'Print label': false,
    'Item Location': false,
  };
  final Map<String, bool> _categoriesOptions = {
    'Add categories': false,
    'Edit categories': false,
    'Delete categories': false,
    'Generic attributes': false,
  };
  final Map<String, bool> _reportsOptions = {
    'View sales report': false,
    'View invoice report': false,
    'View inventory report': false,
  };
  final Map<String, bool> _dashBoardOptions = {
    'Revenue Summary': false,
    'Revenue Total Only': false,
    'Bill Summary': false,
    'Item Summary': false,
  };
  final Map<String, bool> _servicesOptions = {
    'Service orders': false,
    'Services': false,
    'Service reports': false,
  };
  final Map<String, bool> _billsOptions = {
    'View all bills': false,
    'View profile bills only': false,
  };

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    if (widget.userDocumentId.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userDocumentId)
          .collection('subProfiles')
          .doc(widget.profile.id)
          .get();
      if (!doc.exists) return;
      final data = doc.data();
      if (data == null) return;

      final perms = (data['permissions'] as Map?)?.cast<String, dynamic>();
      final items = (data['itemsOptions'] as Map?)?.cast<String, dynamic>();
      final cats = (data['categoriesOptions'] as Map?)?.cast<String, dynamic>();
      final reps = (data['reportsOptions'] as Map?)?.cast<String, dynamic>();
      final dashboardOptions =
          (data['dashBoardOptions'] as Map?)?.cast<String, dynamic>();
      final legacyRevenueOptions =
          (data['revenueSummaryOptions'] as Map?)?.cast<String, dynamic>();
      final services = (data['servicesOptions'] as Map?)?.cast<String, dynamic>();
      final bills = (data['billsOptions'] as Map?)?.cast<String, dynamic>();
      final settings = (data['settingsOptions'] as Map?)?.cast<String, dynamic>();

      if (mounted) {
        setState(() {
          if (perms != null) {
            perms.forEach((k, v) {
              if (_enabled.containsKey(k)) _enabled[k] = (v == true);
            });
            if (_enabled['Dashboard'] != true &&
                perms.containsKey('Revenue Summary')) {
              _enabled['Dashboard'] = perms['Revenue Summary'] == true;
            }
          }
          if (items != null) {
            items.forEach((k, v) {
              if (_itemsOptions.containsKey(k)) _itemsOptions[k] = (v == true);
            });
          }
          if (cats != null) {
            cats.forEach((k, v) {
              if (_categoriesOptions.containsKey(k)) {
                _categoriesOptions[k] = (v == true);
              }
            });
          }
          if (reps != null) {
            reps.forEach((k, v) {
              if (_reportsOptions.containsKey(k)) {
                _reportsOptions[k] = (v == true);
              }
            });
          }
          final optionSource = dashboardOptions ?? legacyRevenueOptions;
          if (optionSource != null) {
            optionSource.forEach((k, v) {
              if (_dashBoardOptions.containsKey(k)) {
                _dashBoardOptions[k] = (v == true);
              }
            });
          }
          if (services != null) {
            services.forEach((k, v) {
              if (_servicesOptions.containsKey(k)) {
                _servicesOptions[k] = (v == true);
              }
            });
          } else if (_enabled['Services'] == true) {
            _servicesOptions['Service orders'] = true;
            _servicesOptions['Services'] = true;
          }
          if (bills != null) {
            bills.forEach((k, v) {
              if (_billsOptions.containsKey(k)) {
                _billsOptions[k] = (v == true);
              }
            });
          } else if (_enabled['Bills'] == true) {
            _billsOptions['View profile bills only'] = true;
          }
          if (settings != null) {
            if (settings['flashOnScan'] != null) {
              _flashOnScan = settings['flashOnScan'] == true;
            }
            if (settings['voiceBillingEnabled'] != null) {
              _voiceBillingEnabled = settings['voiceBillingEnabled'] == true;
            }
            if (settings['barcodeScanningEnabled'] != null) {
              _barcodeScanningEnabled = settings['barcodeScanningEnabled'] == true;
            }
            if (settings['repeatScanning'] != null) {
              _repeatScanning = settings['repeatScanning'] == true;
            }
            if (settings['externalScanner'] != null) {
              _externalScanner = settings['externalScanner'] == true;
            }
            if (settings['scannedItemConfirmation'] != null) {
              _scannedItemConfirmation = settings['scannedItemConfirmation'] == true;
            }
            if (settings['directItemAdditionEnabled'] != null) {
              _directItemAdditionEnabled =
                  settings['directItemAdditionEnabled'] == true;
            }
            if (settings['receiptSize'] != null) {
              _receiptSize = receiptSizeFromRemote(settings['receiptSize']);
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Failed loading subprofile permissions: $e');
      await logErrorToFile(
        'Failed loading subprofile permissions: $e',
        StackTrace.current,
      );
    }
  }

  Map<String, dynamic> _settingsOptionsMap() => {
        'flashOnScan': _flashOnScan,
        'voiceBillingEnabled': _voiceBillingEnabled,
        'barcodeScanningEnabled': _barcodeScanningEnabled,
        'repeatScanning': _repeatScanning,
        'externalScanner': _externalScanner,
        'scannedItemConfirmation': _scannedItemConfirmation,
        'directItemAdditionEnabled': _directItemAdditionEnabled,
        'receiptSize': _receiptSize,
      };

  Future<void> _saveSettings() async {
    if (widget.userDocumentId.isEmpty) return;
    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userDocumentId)
        .collection('subProfiles')
        .doc(widget.profile.id);
    await docRef.set({
      'settingsOptions': _settingsOptionsMap(),
    }, SetOptions(merge: true));
  }

  bool get _areAllPermissionsSelected {
    for (final key in _enabled.keys) {
      if (key == 'Button' ||
          key == 'Items' ||
          key == 'Categories' ||
          key == 'Reports' ||
          key == 'Dashboard' ||
          key == 'Services' ||
          key == 'Bills') {
        continue;
      }
      if (_enabled[key] != true) return false;
    }
    return _itemsOptions.values.every((v) => v) &&
        _categoriesOptions.values.every((v) => v) &&
        _reportsOptions.values.every((v) => v) &&
        _dashBoardOptions.values.every((v) => v) &&
        _servicesOptions.values.every((v) => v) &&
        _billsOptions['View all bills'] == true;
  }

  bool? get _selectAllCheckboxValue {
    if (_areAllPermissionsSelected) return true;
    final anyTopLevel = _enabled.entries.any((e) =>
        e.key != 'Button' &&
        e.key != 'Items' &&
        e.key != 'Categories' &&
        e.key != 'Reports' &&
        e.key != 'Dashboard' &&
        e.key != 'Services' &&
        e.key != 'Bills' &&
        e.value);
    final anySub = _itemsOptions.values.any((v) => v) ||
        _categoriesOptions.values.any((v) => v) ||
        _reportsOptions.values.any((v) => v) ||
        _dashBoardOptions.values.any((v) => v) ||
        _servicesOptions.values.any((v) => v) ||
        _billsOptions.values.any((v) => v);
    if (!anyTopLevel && !anySub) return false;
    return null;
  }

  void _setAllPermissions(bool selected) {
    for (final key in _enabled.keys) {
      if (key != 'Button') {
        _enabled[key] = selected;
      }
    }
    for (final key in _itemsOptions.keys) {
      _itemsOptions[key] = selected;
    }
    for (final key in _categoriesOptions.keys) {
      _categoriesOptions[key] = selected;
    }
    for (final key in _reportsOptions.keys) {
      _reportsOptions[key] = selected;
    }
    for (final key in _dashBoardOptions.keys) {
      _dashBoardOptions[key] = selected;
    }
    for (final key in _servicesOptions.keys) {
      _servicesOptions[key] = selected;
    }
    for (final key in _billsOptions.keys) {
      if (selected) {
        _billsOptions['View all bills'] = true;
        _billsOptions['View profile bills only'] = false;
      } else {
        _billsOptions[key] = false;
      }
    }
  }

  Future<void> _savePermissions() async {
    if (widget.userDocumentId.isEmpty) return;
    _enabled['Items'] = _itemsOptions.values.any((val) => val == true);
    _enabled['Categories'] = _categoriesOptions.values.any(
      (val) => val == true,
    );
    _enabled['Reports'] = _reportsOptions.values.any((val) => val == true);
    _enabled['Dashboard'] =
        _dashBoardOptions.values.any((val) => val == true);
    _enabled['Services'] = _servicesOptions.values.any((val) => val == true);
    _enabled['Bills'] = _billsOptions.values.any((val) => val == true);
    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userDocumentId)
        .collection('subProfiles')
        .doc(widget.profile.id);
    try {
      await docRef.set({
        'permissions': _enabled,
        'itemsOptions': _itemsOptions,
        'categoriesOptions': _categoriesOptions,
        'reportsOptions': _reportsOptions,
        'dashBoardOptions': _dashBoardOptions,
        'servicesOptions': _servicesOptions,
        'billsOptions': _billsOptions,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed saving subprofile permissions: $e');
      await logErrorToFile(
        'Failed saving subprofile permissions: $e',
        StackTrace.current,
      );
      rethrow;
    }
  }

  String formatDateTime(DateTime? date) {
    if (date == null) return 'Not yet synced';
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _handleStatusChange(String newStatus) async {
    if (_isUpdatingStatus ||
        widget.onStatusChanged == null ||
        newStatus == widget.profile.status) {
      return;
    }
    setState(() {
      _isUpdatingStatus = true;
    });
    try {
      await widget.onStatusChanged!(newStatus);
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingStatus = false;
        });
      }
    }
  }

  Future<void> _openStatusChangeModal() async {
    if (widget.onStatusChanged == null || _isUpdatingStatus) return;
    String selectedStatus = widget.profile.status;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('Change Status'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select status'),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selectedStatus,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 'active', child: Text('Active')),
                      DropdownMenuItem(
                        value: 'inactive',
                        child: Text('Inactive'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setModalState(() {
                        selectedStatus = value;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: selectedStatus == widget.profile.status
                      ? null
                      : () async {
                          Navigator.of(context).pop();
                          await _handleStatusChange(selectedStatus);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Update Status'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileColor = generateColorFromCode(widget.profile.code);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundGrey,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              children: [
                ClipOval(
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [profileColor, profileColor.withOpacity(0.8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: profileColor.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        widget.profile.code,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.5,
                          shadows: [
                            Shadow(
                              color: Colors.black26,
                              offset: Offset(1, 1),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            widget.profile.name,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.primaryGreen,
                            ),
                          ),
                          widget.profile.status == 'active'
                              ? Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryWhite.withOpacity(
                                      0.3,
                                    ),
                                    shape: BoxShape.circle,
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black12,
                                        blurRadius: 4,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(2.0),
                                    child: Icon(
                                      Icons.check_circle,
                                      size: 20,
                                      color: AppColors.activeGreen,
                                    ),
                                  ),
                                )
                              : Container(),
                        ],
                      ),
                      const SizedBox(height: 5),
                      widget.profile.status == 'active'
                          ? Text(
                              'Sync status',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.primaryGreen,
                              ),
                            )
                          : Container(),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            'Status:',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.primaryGrey,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: widget.profile.status == 'active'
                                  ? AppColors.activeGreen.withOpacity(0.15)
                                  : Colors.orange.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              widget.profile.status == 'active'
                                  ? 'Active'
                                  : 'Inactive',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: widget.profile.status == 'active'
                                    ? AppColors.activeGreen
                                    : Colors.orange.shade700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          if (widget.onStatusChanged != null)
                            _isUpdatingStatus
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : OutlinedButton(
                                    onPressed: _openStatusChangeModal,
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      minimumSize: const Size(0, 30),
                                      side: BorderSide(
                                        color: AppColors.primaryGreen,
                                      ),
                                    ),
                                    child: Text(
                                      'Change Status',
                                      style: TextStyle(
                                        color: AppColors.primaryGreen,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      widget.profile.status == 'inactive'
                          ? Container()
                          : Row(
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Items:',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.primaryGrey,
                                      ),
                                    ),
                                    Text(
                                      'Bills:',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.primaryGrey,
                                      ),
                                    ),
                                    Text(
                                      'Categories:',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.primaryGrey,
                                      ),
                                    ),
                                    Text(
                                      'Discounts:',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.primaryGrey,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 20),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      formatDateTime(
                                        widget.profile.itemSyncTime,
                                      ),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.primaryGrey,
                                      ),
                                    ),
                                    Text(
                                      formatDateTime(
                                        widget.profile.billSyncTime,
                                      ),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.primaryGrey,
                                      ),
                                    ),
                                    Text(
                                      formatDateTime(
                                        widget.profile.categorySyncTime,
                                      ),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.primaryGrey,
                                      ),
                                    ),
                                    Text(
                                      formatDateTime(
                                        widget.profile.discountSyncTime,
                                      ),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.primaryGrey,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                widget.canActivate
                    ? widget.isActivating
                          ? const CircularProgressIndicator()
                          : SizedBox(
                              width: 80,
                              height: 35,
                              child: ElevatedButton(
                                onPressed: widget.onActivate,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.activeGreen,
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text(
                                  'Activate',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            )
                    : Container(),
              ],
            ),
            // Permissions section
            widget.canActivate
                ? Container()
                : Column(
                    children: [
                      const SizedBox(height: 20),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.primaryWhite,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Theme(
                          data: Theme.of(
                            context,
                          ).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            title: const Text(
                              'Permissions',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            tilePadding: const EdgeInsets.only(
                              right: 15,
                              left: 15,
                            ),
                            initiallyExpanded: _permissionsExpanded,
                            onExpansionChanged: (expanded) {
                              setState(() {
                                _permissionsExpanded = expanded;
                              });
                            },
                            childrenPadding: const EdgeInsets.only(
                              left: 15,
                              right: 8,
                              bottom: 4,
                            ),
                            children: [
                              Column(
                                children: [
                                  CheckboxListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    tristate: true,
                                    title: const Text(
                                      'Select All',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    value: _selectAllCheckboxValue,
                                    onChanged: (_) {
                                      setState(() {
                                        _setAllPermissions(!_areAllPermissionsSelected);
                                      });
                                    },
                                  ),
                                  const Divider(height: 1),
                                  for (final key in _enabled.keys)
                                    if (key != 'Items' &&
                                        key != 'Categories' &&
                                        key != 'Reports' &&
                                        key != 'Dashboard' &&
                                        key != 'Services' &&
                                        key != 'Bills' &&
                                        key != 'Button')
                                      CheckboxListTile(
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(
                                          key,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        value: _enabled[key],
                                        onChanged: (v) {
                                          setState(() {
                                            _enabled[key] = v ?? false;
                                          });
                                        },
                                      )
                                    else if (key == 'Bills')
                                      Theme(
                                        data: Theme.of(context).copyWith(
                                          dividerColor: Colors.transparent,
                                        ),
                                        child: ExpansionTile(
                                          tilePadding: const EdgeInsets.only(
                                            right: 8,
                                            left: 0,
                                          ),
                                          title: const Row(
                                            children: [
                                              Text(
                                                'Bills',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                          childrenPadding:
                                              const EdgeInsets.only(
                                                left: 8,
                                                right: 0,
                                                bottom: 0,
                                              ),
                                          children: [
                                            for (final sub in _billsOptions.keys)
                                              CheckboxListTile(
                                                dense: true,
                                                contentPadding: EdgeInsets.zero,
                                                title: Text(sub),
                                                value: _billsOptions[sub],
                                                onChanged: (v) {
                                                  setState(() {
                                                    final checked = v ?? false;
                                                    if (sub == 'View all bills' &&
                                                        checked) {
                                                      _billsOptions[
                                                              'View profile bills only'] =
                                                          false;
                                                      _billsOptions[sub] = true;
                                                    } else if (sub ==
                                                            'View profile bills only' &&
                                                        checked) {
                                                      _billsOptions[
                                                          'View all bills'] = false;
                                                      _billsOptions[sub] = true;
                                                    } else {
                                                      _billsOptions[sub] = false;
                                                    }
                                                  });
                                                },
                                              ),
                                          ],
                                        ),
                                      )
                                    else if (key == 'Items')
                                      // items option expands to show sub-options
                                      Theme(
                                        data: Theme.of(context).copyWith(
                                          dividerColor: Colors.transparent,
                                        ),
                                        child: ExpansionTile(
                                          tilePadding: const EdgeInsets.only(
                                            right: 8,
                                            left: 0,
                                          ),
                                          title: const Row(
                                            children: [
                                              Text(
                                                'Items',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                          childrenPadding:
                                              const EdgeInsets.only(
                                                left: 8,
                                                right: 0,
                                                bottom: 0,
                                              ),
                                          children: [
                                            for (final sub
                                                in _itemsOptions.keys)
                                              CheckboxListTile(
                                                dense: true,
                                                contentPadding: EdgeInsets.zero,
                                                title: Text(sub),
                                                value: _itemsOptions[sub],
                                                onChanged: (v) {
                                                  setState(() {
                                                    _itemsOptions[sub] =
                                                        v ?? false;
                                                  });
                                                },
                                              ),
                                          ],
                                        ),
                                      )
                                    else if (key == 'Categories')
                                      Theme(
                                        data: Theme.of(context).copyWith(
                                          dividerColor: Colors.transparent,
                                        ),
                                        child: ExpansionTile(
                                          tilePadding: const EdgeInsets.only(
                                            right: 8,
                                            left: 0,
                                          ),
                                          title: const Row(
                                            children: [
                                              Text(
                                                'Categories',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                          childrenPadding:
                                              const EdgeInsets.only(
                                                left: 8,
                                                right: 0,
                                                bottom: 0,
                                              ),
                                          children: [
                                            for (final sub
                                                in _categoriesOptions.keys)
                                              CheckboxListTile(
                                                dense: true,
                                                contentPadding: EdgeInsets.zero,
                                                title: Text(sub),
                                                value: _categoriesOptions[sub],
                                                onChanged: (v) {
                                                  setState(() {
                                                    _categoriesOptions[sub] =
                                                        v ?? false;
                                                  });
                                                },
                                              ),
                                          ],
                                        ),
                                      )
                                    else if (key == 'Reports')
                                      Theme(
                                        data: Theme.of(context).copyWith(
                                          dividerColor: Colors.transparent,
                                        ),
                                        child: ExpansionTile(
                                          tilePadding: const EdgeInsets.only(
                                            right: 8,
                                            left: 0,
                                          ),
                                          title: const Row(
                                            children: [
                                              Text(
                                                'Reports',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                          childrenPadding:
                                              const EdgeInsets.only(
                                                left: 8,
                                                right: 0,
                                                bottom: 0,
                                              ),
                                          children: [
                                            for (final sub
                                                in _reportsOptions.keys)
                                              CheckboxListTile(
                                                dense: true,
                                                contentPadding: EdgeInsets.zero,
                                                title: Text(sub),
                                                value: _reportsOptions[sub],
                                                onChanged: (v) {
                                                  setState(() {
                                                    _reportsOptions[sub] =
                                                        v ?? false;
                                                  });
                                                },
                                              ),
                                          ],
                                        ),
                                      )
                                    else if (key == 'Dashboard')
                                      Theme(
                                        data: Theme.of(context).copyWith(
                                          dividerColor: Colors.transparent,
                                        ),
                                        child: ExpansionTile(
                                          tilePadding: const EdgeInsets.only(
                                            right: 8,
                                            left: 0,
                                          ),
                                          title: const Row(
                                            children: [
                                              Text(
                                                'Dashboard',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                          childrenPadding:
                                              const EdgeInsets.only(
                                                left: 8,
                                                right: 0,
                                                bottom: 0,
                                              ),
                                          children: [
                                            for (final sub
                                                in _dashBoardOptions.keys)
                                              CheckboxListTile(
                                                dense: true,
                                                contentPadding: EdgeInsets.zero,
                                                title: Text(sub),
                                                value: _dashBoardOptions[sub],
                                                onChanged: (v) {
                                                  setState(() {
                                                    _dashBoardOptions[sub] =
                                                        v ?? false;
                                                  });
                                                },
                                              ),
                                          ],
                                        ),
                                      )
                                    else if (key == 'Services')
                                      Theme(
                                        data: Theme.of(context).copyWith(
                                          dividerColor: Colors.transparent,
                                        ),
                                        child: ExpansionTile(
                                          tilePadding: const EdgeInsets.only(
                                            right: 8,
                                            left: 0,
                                          ),
                                          title: const Row(
                                            children: [
                                              Text(
                                                'Services',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                          childrenPadding:
                                              const EdgeInsets.only(
                                                left: 8,
                                                right: 0,
                                                bottom: 0,
                                              ),
                                          children: [
                                            for (final sub
                                                in _servicesOptions.keys)
                                              CheckboxListTile(
                                                dense: true,
                                                contentPadding: EdgeInsets.zero,
                                                title: Text(sub),
                                                value: _servicesOptions[sub],
                                                onChanged: (v) {
                                                  setState(() {
                                                    _servicesOptions[sub] =
                                                        v ?? false;
                                                  });
                                                },
                                              ),
                                          ],
                                        ),
                                      )
                                    else if (key == 'Button')
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 10.0,
                                          bottom: 10.0,
                                          top: 10.0,
                                        ),
                                        child: ElevatedButton(
                                          onPressed: isUpdatingPermission
                                              ? null
                                              : () async {
                                                  if (isUpdatingPermission)
                                                    return;
                                                  setState(() {
                                                    isUpdatingPermission = true;
                                                  });

                                                  try {
                                                    await _savePermissions();
                                                    if (mounted) {
                                                      showSnackbar(
                                                        context,
                                                        'Permissions updated successfully',
                                                        backgroundColor:
                                                            Colors.green,
                                                      );
                                                      setState(() {
                                                        _permissionsExpanded =
                                                            false;
                                                      });
                                                    }
                                                  } catch (e) {
                                                    if (mounted) {
                                                      showSnackbar(
                                                        context,
                                                        'Failed to update permissions: $e',
                                                        backgroundColor:
                                                            Colors.red,
                                                      );
                                                    }
                                                  } finally {
                                                    if (mounted) {
                                                      setState(() {
                                                        isUpdatingPermission =
                                                            false;
                                                      });
                                                    }
                                                  }
                                                },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                AppColors.primaryGreen,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 20,
                                              vertical: 12,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          child: isUpdatingPermission
                                              ? const SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    valueColor:
                                                        AlwaysStoppedAnimation<
                                                          Color
                                                        >(Colors.white),
                                                  ),
                                                )
                                              : const Text(
                                                  'Update Permissions',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                        ),
                                      ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.primaryWhite,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            dividerColor: Colors.transparent,
                          ),
                          child: ExpansionTile(
                            title: const Text(
                              'Settings',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            tilePadding: const EdgeInsets.only(
                              right: 15,
                              left: 15,
                            ),
                            initiallyExpanded: _settingsExpanded,
                            onExpansionChanged: (expanded) {
                              setState(() {
                                _settingsExpanded = expanded;
                              });
                            },
                            childrenPadding: const EdgeInsets.only(
                              left: 8,
                              right: 8,
                              bottom: 4,
                            ),
                            children: [
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Flash on scan'),
                                subtitle: Text(
                                  'Use the camera flash when this sub-profile scans barcodes.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                value: _flashOnScan,
                                onChanged: (val) =>
                                    setState(() => _flashOnScan = val),
                              ),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Voice billing'),
                                subtitle: Text(
                                  'Allow microphone voice search to add items while billing.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                value: _voiceBillingEnabled,
                                onChanged: (val) =>
                                    setState(() => _voiceBillingEnabled = val),
                              ),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Barcode scanning'),
                                subtitle: Text(
                                  'Show barcode scan actions on billing, items, and service screens.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                value: _barcodeScanningEnabled,
                                onChanged: (val) => setState(
                                  () => _barcodeScanningEnabled = val,
                                ),
                              ),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Repeat scanning'),
                                subtitle: Text(
                                  'Keep the scanner ready for the next item after confirming a scan.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                value: _repeatScanning,
                                onChanged: (val) =>
                                    setState(() => _repeatScanning = val),
                              ),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('External scanner'),
                                subtitle: Text(
                                  'Enable Bluetooth SPP barcode scanners.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                value: _externalScanner,
                                onChanged: (val) =>
                                    setState(() => _externalScanner = val),
                              ),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Scanned item confirmation'),
                                subtitle: Text(
                                  'Show a quantity dialog before each scanned item is added.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                value: _scannedItemConfirmation,
                                onChanged: (val) => setState(
                                  () => _scannedItemConfirmation = val,
                                ),
                              ),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Direct item addition'),
                                subtitle: Text(
                                  'Show quick-add shortcuts on billing and service screens.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                value: _directItemAdditionEnabled,
                                onChanged: (val) => setState(
                                  () => _directItemAdditionEnabled = val,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 8, bottom: 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Receipt size',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      'Paper width for bill receipts on this sub-profile\'s printer.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    DropdownButtonFormField<String>(
                                      value: _receiptSize,
                                      isExpanded: true,
                                      items: RECEIPT_SIZE_OPTIONS
                                          .map(
                                            (size) => DropdownMenuItem(
                                              value: size,
                                              child: Text(size),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (val) {
                                        if (val == null) return;
                                        setState(() => _receiptSize = val);
                                      },
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.only(
                                  right: 10.0,
                                  bottom: 10.0,
                                  top: 4.0,
                                ),
                                child: ElevatedButton(
                                  onPressed: isUpdatingSettings
                                      ? null
                                      : () async {
                                          if (isUpdatingSettings) return;
                                          setState(() {
                                            isUpdatingSettings = true;
                                          });
                                          try {
                                            await _saveSettings();
                                            if (mounted) {
                                              showSnackbar(
                                                context,
                                                'Settings updated successfully',
                                                backgroundColor: Colors.green,
                                              );
                                              setState(() {
                                                _settingsExpanded = false;
                                              });
                                            }
                                          } catch (e) {
                                            if (mounted) {
                                              showSnackbar(
                                                context,
                                                'Failed to update settings: $e',
                                                backgroundColor: Colors.red,
                                              );
                                            }
                                          } finally {
                                            if (mounted) {
                                              setState(() {
                                                isUpdatingSettings = false;
                                              });
                                            }
                                          }
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primaryGreen,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: isUpdatingSettings
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                          ),
                                        )
                                      : const Text(
                                          'Update Settings',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}

Future<bool?> _showActivateConfirmation(
  BuildContext context,
  SubProfileModel profile,
  bool hasExistingBills,
) async {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Row(
          children: [
            Icon(
              Icons.person_pin_circle,
              color: AppColors.primaryGreen,
              size: 24,
            ),
            const SizedBox(width: 8),
            const Text(
              'Activate Profile',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Profile Avatar
            CircleAvatar(
              radius: 30,
              backgroundColor: generateColorFromCode(profile.code),
              child: Text(
                profile.code,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(height: 15),
            // Profile Name
            Text(
              profile.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            // Profile Code
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: generateColorFromCode(profile.code).withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: generateColorFromCode(profile.code).withOpacity(0.3),
                ),
              ),
              child: Text(
                'Code: ${profile.code}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: generateColorFromCode(profile.code),
                ),
              ),
            ),
            const SizedBox(height: 15),
            // Bills warning message
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: hasExistingBills ? Colors.blue[50] : Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: hasExistingBills
                      ? Colors.blue[200]!
                      : Colors.orange[200]!,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    hasExistingBills
                        ? Icons.receipt_long
                        : Icons.warning_amber_rounded,
                    color: hasExistingBills
                        ? Colors.blue[700]
                        : Colors.orange[700],
                    size: 24,
                  ),
                  const SizedBox(height: 8),
                  if (hasExistingBills) ...[
                    Text(
                      'Existing Bills Found',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.blue[800],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'You will lose access to existing bills when switching to this profile.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ] else ...[
                    Text(
                      'Profile Activation',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.orange[800],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Once activated, you cannot undo this action. This will become your active profile.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              'Activate Profile',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      );
    },
  );
}

Future<bool?> _showDeleteConfirmation(
  BuildContext context,
  SubProfileModel profile,
) async {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text(
          'Delete Profile',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.orange,
              size: 50,
            ),
            const SizedBox(height: 15),
            Text(
              'Are you sure you want to delete "${profile.name}"?',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 10),
            Text(
              'This action cannot be undone.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Delete',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      );
    },
  );
}
