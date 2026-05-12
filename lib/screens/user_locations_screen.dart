import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/sub_profile_model.dart';
import '../models/user_location_model.dart';
import '../utils/app_colors.dart';

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

  @override
  void initState() {
    super.initState();
    if (widget.initialBootstrap != null) {
      _applyBootstrap(widget.initialBootstrap!);
      _loading = false;
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
      _selectedByLocation[loc.id] = Set<String>.from(loc.subProfileIds);
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
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
      locs.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

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
        final old = _locations[idx];
        _locations[idx] = UserLocationModel(
          id: old.id,
          name: old.name,
          businessName: old.businessName,
          businessPhoneNumber: old.businessPhoneNumber,
          businessGstNumber: old.businessGstNumber,
          gstType: old.gstType,
          address: old.address,
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

  Future<void> _confirmDeleteLocation(UserLocationModel location) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete location?'),
        content: Text(
          'Delete "${location.name}"? This cannot be undone.',
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

    final nameController = TextEditingController(text: existing?.name ?? '');
    final businessNameController = TextEditingController(text: existing?.businessName ?? '');
    final businessPhoneController = TextEditingController(text: existing?.businessPhoneNumber ?? '');
    final businessGstController = TextEditingController(text: existing?.businessGstNumber ?? '');
    final addressController = TextEditingController(text: existing?.address ?? '');
    String selectedGstType = (existing?.gstType ?? '').trim().isNotEmpty
        ? existing!.gstType
        : 'Regular';
    const gstChoices = ['Regular', 'Composition', 'Unregistered'];
    if (!gstChoices.contains(selectedGstType)) {
      selectedGstType = 'Regular';
    }

    final formKey = GlobalKey<FormState>();

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
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                            existing == null ? 'Add Location' : 'Edit Location',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: nameController,
                            decoration: const InputDecoration(
                              labelText: 'Location name',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty) ? 'Please enter a location name' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: businessNameController,
                            decoration: const InputDecoration(
                              labelText: 'Business name',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty) ? 'Please enter a business name' : null,
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
                              if (t.isEmpty) return 'Please enter business phone number';
                              if (t.length != 10) return 'Enter a 10-digit phone number';
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
                              DropdownMenuItem(value: 'Regular', child: Text('Regular')),
                              DropdownMenuItem(value: 'Composition', child: Text('Composition')),
                              DropdownMenuItem(value: 'Unregistered', child: Text('Unregistered')),
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
                              final showGst = t == 'regular' || t == 'composition';
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
                                      if (value == null || value.trim().isEmpty) {
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
                            validator: (v) =>
                                (v == null || v.trim().isEmpty) ? 'Please enter a location address' : null,
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () async {
                                FocusManager.instance.primaryFocus?.unfocus();
                                if (formKey.currentState?.validate() != true) return;
                                final gstT = selectedGstType.trim().toLowerCase();
                                final gstRequired = gstT == 'regular' || gstT == 'composition';
                                final gstSave = gstRequired ? businessGstController.text.trim() : '';

                                final payload = <String, dynamic>{
                                  'name': nameController.text.trim(),
                                  'businessName': businessNameController.text.trim(),
                                  'businessPhoneNumber': businessPhoneController.text.trim(),
                                  'businessGstNumber': gstSave,
                                  'gstType': selectedGstType,
                                  'address': addressController.text.trim(),
                                  'updatedAt': FieldValue.serverTimestamp(),
                                };

                                try {
                                  if (existing == null) {
                                    payload['subProfileIds'] = <String>[];
                                    payload['createdAt'] = FieldValue.serverTimestamp();
                                    await widget.userRef.collection('locations').add(payload);
                                  } else {
                                    payload['subProfileIds'] = existing.subProfileIds;
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
                                      SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
                                    );
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryGreen,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: Text(existing == null ? 'Save Location' : 'Update Location'),
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
                    child: _locations.isEmpty
                        ? Center(
                            child: Text(
                              'No locations added yet',
                              style: TextStyle(fontSize: 13, color: AppColors.primaryGrey),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _locations.length,
                            itemBuilder: (context, index) {
                              final location = _locations[index];
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
                                            color: saving || deleting ? AppColors.primaryGrey : AppColors.primaryText,
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
                                              : Icon(Icons.delete_outline_rounded, color: AppColors.primaryRed),
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
                                            child: Icon(Icons.location_on_outlined, size: 14, color: AppColors.primaryGrey),
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
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: mappable.map((profile) {
                                        final isSelected = selected.contains(profile.id);
                                        final blockedElsewhere =
                                            _isMappedElsewhere(location.id, profile.id) && !isSelected;
                                        final saving = _savingLocationIds.contains(location.id);

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
                                                  await _updateMappings(location.id, Set<String>.from(selected));
                                                },
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ),
                              );
                            },
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
  locs.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  final subs = <SubProfileModel>[];
  for (final d in subSnap.docs) {
    try {
      subs.add(SubProfileModel.fromMap(d.data(), d.id));
    } catch (_) {}
  }

  return UserLocationsBootstrap(locations: locs, subProfiles: subs);
}
