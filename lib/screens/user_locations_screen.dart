import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/sub_profile_model.dart';
import '../models/user_location_model.dart';
import '../utils/app_colors.dart';
import 'location_map_view.dart';

/// Bootstrap payload from [CustomersScreen] prefetch (optional).
class UserLocationsBootstrap {
  final List<UserLocationModel> locations;
  final List<SubProfileModel> subProfiles;

  UserLocationsBootstrap({
    required this.locations,
    required this.subProfiles,
  });
}

/// Mirrors mobile `LocationView`: list locations, map subprofiles per location, add/edit/delete.
class UserLocationsScreen extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> userRef;
  final String displayName;
  final UserLocationsBootstrap? initialBootstrap;

  const UserLocationsScreen({
    super.key,
    required this.userRef,
    required this.displayName,
    this.initialBootstrap,
  });

  @override
  State<UserLocationsScreen> createState() => _UserLocationsScreenState();
}

class _UserLocationsScreenState extends State<UserLocationsScreen> {
  static const Color _brand50 = Color(0xFFEEF2FF);
  static const Color _brand100 = Color(0xFFE0E7FF);
  static const Color _border = Color(0xFFE2E8F0);

  bool _loading = true;
  String? _error;
  List<UserLocationModel> _locations = [];
  List<SubProfileModel> _subProfiles = [];
  final Map<String, Set<String>> _selectedByLocation = {};
  final Set<String> _savingLocationIds = {};
  final Set<String> _deletingLocationIds = {};

  /// Fallback business fields from the parent user doc (for default location card).
  String _userBusinessName = '';
  String _userBusinessAddress = '';
  String _userBusinessPhone = '';
  String _userBusinessGst = '';
  String _userGstType = 'Regular';

  UserLocationModel _copyLocation(
    UserLocationModel old, {
    String? name,
    String? businessName,
    String? businessPhoneNumber,
    String? businessGstNumber,
    String? gstType,
    String? address,
    double? latitude,
    double? longitude,
    bool clearCoordinates = false,
    List<String>? subProfileIds,
    bool? isDefault,
  }) {
    return UserLocationModel(
      id: old.id,
      name: name ?? old.name,
      businessName: businessName ?? old.businessName,
      businessPhoneNumber: businessPhoneNumber ?? old.businessPhoneNumber,
      businessGstNumber: businessGstNumber ?? old.businessGstNumber,
      gstType: gstType ?? old.gstType,
      address: address ?? old.address,
      latitude: clearCoordinates ? null : (latitude ?? old.latitude),
      longitude: clearCoordinates ? null : (longitude ?? old.longitude),
      subProfileIds: subProfileIds ?? old.subProfileIds,
      isDefault: isDefault ?? old.isDefault,
    );
  }

  Future<LocationMapResult?> _openLocationMap({
    double? latitude,
    double? longitude,
    String initialQuery = '',
  }) {
    return Navigator.push<LocationMapResult>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationMapView(
          initialLatitude: latitude,
          initialLongitude: longitude,
          initialQuery: initialQuery,
        ),
      ),
    );
  }

  Widget _mapPinButton({
    required bool pinned,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(
        pinned ? Icons.location_on : Icons.add_location_alt_outlined,
        size: 18,
      ),
      label: Text(pinned ? 'Change location' : 'Set location on map'),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialBootstrap != null) {
      _applyBootstrap(widget.initialBootstrap!);
      _loading = false;
      _loadUserPlanAndBusiness().then((_) {
        if (mounted) setState(() {});
      });
    } else {
      _reload();
    }
  }

  void _applyBootstrap(UserLocationsBootstrap b) {
    _locations = List.from(b.locations);
    _locations.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _subProfiles = List.from(b.subProfiles);
    _syncSelectionMaps();
  }

  void _syncSelectionMaps() {
    for (final loc in _locations) {
      if (loc.isDefault) continue;
      _selectedByLocation[loc.id] = Set<String>.from(loc.subProfileIds);
    }
  }

  UserLocationModel? get _defaultLocation {
    for (final l in _locations) {
      if (l.isDefault) return l;
    }
    return null;
  }

  List<UserLocationModel> get _additionalLocations =>
      _locations.where((l) => !l.isDefault).toList();

  Future<void> _loadUserPlanAndBusiness() async {
    try {
      final userSnap = await widget.userRef.get();
      final data = userSnap.data() ?? <String, dynamic>{};
      _userBusinessName = (data['name'] ?? data['businessName'] ?? '')
          .toString()
          .trim();
      _userBusinessAddress = (data['address'] ?? '').toString().trim();
      _userBusinessPhone = (data['phone'] ?? data['businessPhoneNumber'] ?? '')
          .toString()
          .trim();
      _userBusinessGst = (data['gstNumber'] ?? data['businessGstNumber'] ?? '')
          .toString()
          .trim();
      final gstRaw = (data['gstType'] ?? data['gst_type'] ?? 'Regular')
          .toString()
          .trim();
      _userGstType = gstRaw.isEmpty ? 'Regular' : gstRaw;
    } catch (e) {
      debugPrint('Failed loading user business for locations: $e');
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _loadUserPlanAndBusiness();
      final locSnap = await widget.userRef.collection('locations').get();
      final subSnap = await widget.userRef.collection('subProfiles').get();

      final locs = <UserLocationModel>[];
      for (final d in locSnap.docs) {
        try {
          locs.add(UserLocationModel.fromFirestore(d));
        } catch (e) {
          debugPrint('Parse location ${d.id}: $e');
        }
      }
      locs.sort((a, b) {
        if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      final subs = <SubProfileModel>[];
      for (final d in subSnap.docs) {
        try {
          subs.add(SubProfileModel.fromMap(d.data(), d.id));
        } catch (e) {
          debugPrint('Parse subprofile ${d.id}: $e');
        }
      }

      if (!mounted) return;
      setState(() {
        _locations = locs;
        _subProfiles = subs;
        _selectedByLocation.clear();
        _syncSelectionMaps();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<SubProfileModel> get _mappableProfiles =>
      _subProfiles.where((p) => p.code.trim().toUpperCase() != 'SA').toList();

  bool _isMappedElsewhere(String locationId, String profileId) {
    for (final e in _selectedByLocation.entries) {
      if (e.key == locationId) continue;
      if (e.value.contains(profileId)) return true;
    }
    return false;
  }

  Future<void> _updateMappings(String locationId, Set<String> selected) async {
    setState(() => _savingLocationIds.add(locationId));
    try {
      await widget.userRef.collection('locations').doc(locationId).set(
        {
          'subProfileIds': selected.toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      final idx = _locations.indexWhere((l) => l.id == locationId);
      if (idx >= 0) {
        _locations[idx] = _copyLocation(
          _locations[idx],
          subProfileIds: selected.toList(),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update mappings: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _savingLocationIds.remove(locationId));
    }
  }

  Future<int> _countItemsMappedToLocation(String locationId) async {
    try {
      final snap = await widget.userRef
          .collection('items')
          .where('location_id', isEqualTo: locationId)
          .get();
      return snap.docs.length;
    } catch (e) {
      debugPrint('Failed counting items for location $locationId: $e');
      // Fallback: scan a bounded set if index/query fails
      try {
        final all = await widget.userRef.collection('items').limit(2000).get();
        var count = 0;
        for (final d in all.docs) {
          final data = d.data();
          final id = (data['location_id'] ?? data['locationId'] ?? '')
              .toString()
              .trim();
          if (id == locationId) count++;
        }
        return count;
      } catch (_) {
        return 0;
      }
    }
  }

  Future<void> _confirmDeleteLocation(UserLocationModel location) async {
    if (location.isDefault) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Default location cannot be deleted'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final linkedCount = await _countItemsMappedToLocation(location.id);
    if (!mounted) return;

    if (linkedCount > 0) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Cannot delete location'),
          content: Text(
            '"${location.name}" has $linkedCount item(s) mapped to it. '
            'Remove or reassign those items before deleting this location.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete location?'),
        content: Text(
          'No items are mapped to "${location.name}". This action cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deletingLocationIds.add(location.id));
    try {
      await widget.userRef.collection('locations').doc(location.id).delete();
      _selectedByLocation.remove(location.id);
      _locations.removeWhere((l) => l.id == location.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location deleted'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _deletingLocationIds.remove(location.id));
    }
  }

  Future<void> _showDefaultLocationNameModal(
    UserLocationModel defaultLocation,
  ) async {
    final nameController = TextEditingController(text: defaultLocation.name);
    final addressController = TextEditingController(
      text: defaultLocation.address.trim().isNotEmpty
          ? defaultLocation.address
          : _userBusinessAddress,
    );
    final formKey = GlobalKey<FormState>();
    var saving = false;
    double? latitude = defaultLocation.latitude;
    double? longitude = defaultLocation.longitude;
    var clearCoordinates = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Edit default location',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Items without a mapped location use this name.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.primaryGrey,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Location name',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Location name is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: addressController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Location address',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter a location address';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        _mapPinButton(
                          pinned: !clearCoordinates &&
                              latitude != null &&
                              longitude != null,
                          onPressed: () async {
                            final result = await _openLocationMap(
                              latitude: clearCoordinates ? null : latitude,
                              longitude: clearCoordinates ? null : longitude,
                              initialQuery: addressController.text.trim(),
                            );
                            if (result == null) return;
                            setModalState(() {
                              if (result.cleared) {
                                latitude = null;
                                longitude = null;
                                clearCoordinates = true;
                              } else {
                                latitude = result.latitude;
                                longitude = result.longitude;
                                clearCoordinates = false;
                                final picked = result.address?.trim() ?? '';
                                if (picked.isNotEmpty) {
                                  addressController.text = picked;
                                }
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: saving
                              ? null
                              : () async {
                                  if (!formKey.currentState!.validate()) return;
                                  setModalState(() => saving = true);
                                  try {
                                    final name = nameController.text.trim();
                                    final address =
                                        addressController.text.trim();
                                    final payload = <String, dynamic>{
                                      'name': name,
                                      'address': address,
                                      'updatedAt': FieldValue.serverTimestamp(),
                                    };
                                    if (clearCoordinates) {
                                      payload['latitude'] = FieldValue.delete();
                                      payload['longitude'] =
                                          FieldValue.delete();
                                    } else {
                                      payload['latitude'] = latitude;
                                      payload['longitude'] = longitude;
                                    }
                                    await widget.userRef
                                        .collection('locations')
                                        .doc(defaultLocation.id)
                                        .set(
                                          payload,
                                          SetOptions(merge: true),
                                        );
                                    final idx = _locations.indexWhere(
                                      (l) => l.id == defaultLocation.id,
                                    );
                                    if (idx >= 0) {
                                      _locations[idx] = _copyLocation(
                                        _locations[idx],
                                        name: name,
                                        address: address,
                                        latitude: latitude,
                                        longitude: longitude,
                                        clearCoordinates: clearCoordinates,
                                        isDefault: true,
                                      );
                                    }
                                    if (mounted) setState(() {});
                                    if (ctx.mounted) Navigator.pop(ctx);
                                  } catch (e) {
                                    if (ctx.mounted) {
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Failed to update location: $e',
                                          ),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (ctx.mounted) {
                                      setModalState(() => saving = false);
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Save'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    nameController.dispose();
    addressController.dispose();
  }

  Future<void> _showLocationModal({String? locationId}) async {
    UserLocationModel? existing;
    if (locationId != null) {
      for (final l in _locations) {
        if (l.id == locationId) {
          existing = l;
          break;
        }
      }
      if (existing == null) return;
    }

    final isEdit = existing != null;
    final nameController = TextEditingController(text: existing?.name ?? '');
    final businessNameController = TextEditingController(
      text: (existing?.businessName ?? '').trim().isNotEmpty
          ? existing!.businessName
          : _userBusinessName,
    );
    final businessPhoneController = TextEditingController(
      text: (existing?.businessPhoneNumber ?? '').trim().isNotEmpty
          ? existing!.businessPhoneNumber
          : _userBusinessPhone,
    );
    final businessGstController = TextEditingController(
      text: (existing?.businessGstNumber ?? '').trim().isNotEmpty
          ? existing!.businessGstNumber
          : _userBusinessGst,
    );
    final addressController = TextEditingController(
      text: (existing?.address ?? '').trim().isNotEmpty
          ? existing!.address
          : _userBusinessAddress,
    );
    String selectedGstType = (existing?.gstType ?? '').trim().isNotEmpty
        ? existing!.gstType
        : (_userGstType.trim().isNotEmpty ? _userGstType : 'Regular');
    const gstChoices = ['Regular', 'Composition', 'Unregistered'];
    if (!gstChoices.contains(selectedGstType)) {
      selectedGstType = 'Regular';
    }
    final initialGstT = selectedGstType.trim().toLowerCase();
    if (initialGstT != 'regular' && initialGstT != 'composition') {
      businessGstController.text = '';
    }

    final formKey = GlobalKey<FormState>();
    double? latitude = existing?.latitude;
    double? longitude = existing?.longitude;
    var clearCoordinates = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final bottom = MediaQuery.of(ctx).viewInsets.bottom;
            return SafeArea(
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(bottom: bottom),
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: Form(
                      key: formKey,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEdit ? 'Edit Location' : 'Add Location',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: nameController,
                            decoration: const InputDecoration(
                              labelText: 'Location name',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Please enter a location name'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: businessNameController,
                            decoration: const InputDecoration(
                              labelText: 'Business name',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Please enter a business name'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: businessPhoneController,
                            decoration: const InputDecoration(
                              labelText: 'Business phone number',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.phone,
                            maxLength: 10,
                            validator: (v) {
                              final t = (v ?? '').trim();
                              if (t.isEmpty) {
                                return 'Please enter business phone number';
                              }
                              if (t.length != 10) {
                                return 'Enter a 10-digit phone number';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            key: ValueKey<String>('gst_$selectedGstType'),
                            initialValue: selectedGstType,
                            decoration: const InputDecoration(
                              labelText: 'GST Type',
                              border: OutlineInputBorder(),
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
                            onChanged: (value) {
                              if (value == null) return;
                              setModalState(() {
                                selectedGstType = value;
                                final v = value.trim().toLowerCase();
                                if (v != 'regular' && v != 'composition') {
                                  businessGstController.clear();
                                }
                              });
                            },
                          ),
                          Builder(
                            builder: (context) {
                              final t = selectedGstType.trim().toLowerCase();
                              final showGst =
                                  t == 'regular' || t == 'composition';
                              if (!showGst) return const SizedBox.shrink();
                              return Column(
                                children: [
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: businessGstController,
                                    decoration: const InputDecoration(
                                      labelText: 'Business GST number',
                                      border: OutlineInputBorder(),
                                    ),
                                    validator: (value) {
                                      if (!showGst) return null;
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'Please enter business GST number';
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: addressController,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Location address',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Please enter a location address'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          _mapPinButton(
                            pinned: !clearCoordinates &&
                                latitude != null &&
                                longitude != null,
                            onPressed: () async {
                              final result = await _openLocationMap(
                                latitude: clearCoordinates ? null : latitude,
                                longitude: clearCoordinates ? null : longitude,
                                initialQuery: addressController.text.trim(),
                              );
                              if (result == null) return;
                              setModalState(() {
                                if (result.cleared) {
                                  latitude = null;
                                  longitude = null;
                                  clearCoordinates = true;
                                } else {
                                  latitude = result.latitude;
                                  longitude = result.longitude;
                                  clearCoordinates = false;
                                  final picked = result.address?.trim() ?? '';
                                  if (picked.isNotEmpty) {
                                    addressController.text = picked;
                                  }
                                }
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () async {
                                FocusManager.instance.primaryFocus?.unfocus();
                                if (formKey.currentState?.validate() != true) {
                                  return;
                                }
                                final gstT =
                                    selectedGstType.trim().toLowerCase();
                                final gstRequired =
                                    gstT == 'regular' || gstT == 'composition';
                                final gstSave = gstRequired
                                    ? businessGstController.text.trim()
                                    : '';

                                final payload = <String, dynamic>{
                                  'name': nameController.text.trim(),
                                  'businessName':
                                      businessNameController.text.trim(),
                                  'businessPhoneNumber':
                                      businessPhoneController.text.trim(),
                                  'businessGstNumber': gstSave,
                                  'gstType': selectedGstType,
                                  'address': addressController.text.trim(),
                                  'updatedAt': FieldValue.serverTimestamp(),
                                };
                                if (clearCoordinates) {
                                  payload['latitude'] = FieldValue.delete();
                                  payload['longitude'] = FieldValue.delete();
                                } else {
                                  payload['latitude'] = latitude;
                                  payload['longitude'] = longitude;
                                }

                                try {
                                  if (!isEdit) {
                                    payload['subProfileIds'] = <String>[];
                                    payload['isDefault'] = false;
                                    payload['createdAt'] =
                                        FieldValue.serverTimestamp();
                                    await widget.userRef
                                        .collection('locations')
                                        .add(payload);
                                  } else {
                                    payload['subProfileIds'] =
                                        existing!.subProfileIds;
                                    payload['isDefault'] = existing.isDefault;
                                    await widget.userRef
                                        .collection('locations')
                                        .doc(existing.id)
                                        .set(payload, SetOptions(merge: true));
                                  }
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  await _reload();
                                } catch (e) {
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                        content: Text('Save failed: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryGreen,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: Text(
                                isEdit ? 'Update Location' : 'Save Location',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    nameController.dispose();
    businessNameController.dispose();
    businessPhoneController.dispose();
    businessGstController.dispose();
    addressController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mappable = _mappableProfiles;

    return Scaffold(
      backgroundColor: AppColors.primaryWhite,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: AppColors.primaryText, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: Text(
          'Locations — ${widget.displayName}',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryText,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(onPressed: _reload, child: const Text('Retry')),
                  ],
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _brand50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _brand100),
                    ),
                    child: Text(
                      'Create multiple locations and map subprofiles for each location.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: AppColors.primaryText,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      children: [
                        if (_defaultLocation != null)
                          _buildDefaultLocationCard(_defaultLocation!),
                        if (_additionalLocations.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 24),
                            child: Center(
                              child: Text(
                                'No additional locations added yet',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.primaryGrey,
                                ),
                              ),
                            ),
                          )
                        else
                          ..._additionalLocations.map(
                            (location) => _buildAdditionalLocationCard(
                              location,
                              mappable,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showLocationModal(),
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: AppColors.primaryWhite,
        shape: const CircleBorder(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildDefaultLocationCard(UserLocationModel defaultLocation) {
    final saving = _savingLocationIds.contains(defaultLocation.id);
    final displayAddress = defaultLocation.address.trim().isNotEmpty
        ? defaultLocation.address.trim()
        : _userBusinessAddress;
    final displayBusinessName = defaultLocation.businessName.trim().isNotEmpty
        ? defaultLocation.businessName.trim()
        : _userBusinessName;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _brand50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _brand100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  defaultLocation.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryText,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.highlightGreen,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Default',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.successGreen,
                  ),
                ),
              ),
              IconButton(
                onPressed: saving
                    ? null
                    : () => _showDefaultLocationNameModal(defaultLocation),
                icon: Icon(
                  Icons.edit_outlined,
                  color: saving ? AppColors.primaryGrey : AppColors.primaryText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Uses your main business address. Items not assigned to another location appear under this name.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.primaryGrey,
              height: 1.4,
            ),
          ),
          if (displayBusinessName.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Business: $displayBusinessName',
              style: TextStyle(fontSize: 12, color: AppColors.primaryGrey),
            ),
          ],
          if (displayAddress.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.location_on_outlined,
                    size: 14,
                    color: AppColors.primaryGrey,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    displayAddress,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.primaryGrey,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (defaultLocation.hasMapPin) ...[
            const SizedBox(height: 4),
            Text(
              'Pinned on map',
              style: TextStyle(fontSize: 12, color: AppColors.successGreen),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAdditionalLocationCard(
    UserLocationModel location,
    List<SubProfileModel> mappable,
  ) {
    final selected = _selectedByLocation.putIfAbsent(
      location.id,
      () => Set<String>.from(location.subProfileIds),
    );
    if (selected.isEmpty && location.subProfileIds.isNotEmpty) {
      selected.addAll(location.subProfileIds);
    }

    final saving = _savingLocationIds.contains(location.id);
    final deleting = _deletingLocationIds.contains(location.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  location.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryText,
                  ),
                ),
              ),
              IconButton(
                onPressed: saving || deleting
                    ? null
                    : () => _showLocationModal(locationId: location.id),
                icon: Icon(
                  Icons.edit_outlined,
                  color: saving || deleting
                      ? AppColors.primaryGrey
                      : AppColors.primaryText,
                ),
              ),
              IconButton(
                onPressed: saving || deleting
                    ? null
                    : () => _confirmDeleteLocation(location),
                icon: deleting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.primaryRed,
                      ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (location.gstType.isNotEmpty)
            Text(
              'GST Type: ${location.gstType}',
              style: TextStyle(fontSize: 12, color: AppColors.primaryGrey),
            ),
          if (location.businessName.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Business: ${location.businessName}',
              style: TextStyle(fontSize: 12, color: AppColors.primaryGrey),
            ),
          ],
          if (location.businessPhoneNumber.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Phone: ${location.businessPhoneNumber}',
              style: TextStyle(fontSize: 12, color: AppColors.primaryGrey),
            ),
          ],
          if (location.businessGstNumber.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'GST No: ${location.businessGstNumber}',
              style: TextStyle(fontSize: 12, color: AppColors.primaryGrey),
            ),
          ],
          if (location.address.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.location_on_outlined,
                    size: 14,
                    color: AppColors.primaryGrey,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    location.address,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.primaryGrey,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (location.hasMapPin) ...[
            const SizedBox(height: 4),
            Text(
              'Pinned on map',
              style: TextStyle(fontSize: 12, color: AppColors.successGreen),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: mappable.map((profile) {
              final isSelected = selected.contains(profile.id);
              final blockedElsewhere =
                  _isMappedElsewhere(location.id, profile.id) && !isSelected;

              return FilterChip(
                label: Text('${profile.name} (${profile.code})'),
                selected: isSelected,
                showCheckmark: true,
                backgroundColor: AppColors.backgroundSuccess,
                selectedColor: AppColors.highlightGreen,
                checkmarkColor: AppColors.successGreen,
                side: BorderSide(
                  color: isSelected ? AppColors.successGreen : _border,
                ),
                onSelected: (blockedElsewhere && !isSelected) || saving
                    ? null
                    : (val) async {
                        setState(() {
                          if (val) {
                            selected.add(profile.id);
                          } else {
                            selected.remove(profile.id);
                          }
                        });
                        await _updateMappings(
                          location.id,
                          Set<String>.from(selected),
                        );
                      },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

Future<UserLocationsBootstrap> loadUserLocationsBootstrap(
  DocumentReference<Map<String, dynamic>> userRef,
) async {
  final locSnap = await userRef.collection('locations').get();
  final subSnap = await userRef.collection('subProfiles').get();

  final locs = <UserLocationModel>[];
  for (final d in locSnap.docs) {
    try {
      locs.add(UserLocationModel.fromFirestore(d));
    } catch (_) {}
  }
  locs.sort((a, b) {
    if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

  final subs = <SubProfileModel>[];
  for (final d in subSnap.docs) {
    try {
      subs.add(SubProfileModel.fromMap(d.data(), d.id));
    } catch (_) {}
  }

  return UserLocationsBootstrap(locations: locs, subProfiles: subs);
}
