import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../utils/app_colors.dart';

class LocationMapResult {
  const LocationMapResult({
    this.latitude,
    this.longitude,
    this.address,
    this.cleared = false,
  });

  final double? latitude;
  final double? longitude;
  final String? address;
  final bool cleared;
}

class _AddressHit {
  const _AddressHit({required this.label, required this.point});

  final String label;
  final LatLng point;
}

class LocationMapView extends StatefulWidget {
  const LocationMapView({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.initialQuery = '',
  });

  final double? initialLatitude;
  final double? initialLongitude;
  final String initialQuery;

  @override
  State<LocationMapView> createState() => _LocationMapViewState();
}

class _LocationMapViewState extends State<LocationMapView> {
  static const LatLng _fallbackCenter = LatLng(20.5937, 78.9629);

  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  List<_AddressHit> _results = [];
  bool _searching = false;
  bool _resolving = false;
  LatLng? _selected;
  String? _selectedLabel;

  bool get _hasInitialPin =>
      widget.initialLatitude != null && widget.initialLongitude != null;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.initialQuery;
    if (_hasInitialPin) {
      _selected = LatLng(widget.initialLatitude!, widget.initialLongitude!);
    } else if (widget.initialQuery.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search());
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _searching = true;
      _results = [];
    });
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'jsonv2',
        'limit': '6',
      });
      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'XeebillAdmin/1.0 (location picker)',
          'Accept': 'application/json',
        },
      );
      if (!mounted) return;
      if (response.statusCode != 200) {
        setState(() => _searching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not search that address'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      final decoded = jsonDecode(response.body);
      final hits = <_AddressHit>[];
      if (decoded is List) {
        for (final row in decoded) {
          if (row is! Map) continue;
          final lat = double.tryParse(row['lat']?.toString() ?? '');
          final lon = double.tryParse(row['lon']?.toString() ?? '');
          final label = row['display_name']?.toString() ?? '';
          if (lat == null || lon == null || label.isEmpty) continue;
          hits.add(_AddressHit(label: label, point: LatLng(lat, lon)));
        }
      }
      setState(() {
        _results = hits;
        _searching = false;
      });
      if (hits.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No places matched that address'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _searching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not search that address'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _choose(_AddressHit hit) {
    setState(() {
      _selected = hit.point;
      _selectedLabel = hit.label;
      _results = [];
    });
    _mapController.move(hit.point, 16);
  }

  Future<String?> _addressForPoint(LatLng point) async {
    final known = _selectedLabel?.trim() ?? '';
    if (known.isNotEmpty) return known;
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'lat': point.latitude.toString(),
      'lon': point.longitude.toString(),
      'format': 'jsonv2',
    });
    final response = await http.get(
      uri,
      headers: {
        'User-Agent': 'XeebillAdmin/1.0 (location picker)',
        'Accept': 'application/json',
      },
    );
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return null;
    final label = decoded['display_name']?.toString().trim() ?? '';
    return label.isEmpty ? null : label;
  }

  Future<void> _useSelected() async {
    final point = _selected;
    if (point == null || _resolving) return;
    setState(() => _resolving = true);
    String? address;
    try {
      address = await _addressForPoint(point);
    } catch (_) {
      address = null;
    }
    if (!mounted) return;
    setState(() => _resolving = false);
    if (address == null || address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not read the address for this pin'),
          backgroundColor: Colors.orange,
        ),
      );
    }
    Navigator.pop(
      context,
      LocationMapResult(
        latitude: point.latitude,
        longitude: point.longitude,
        address: address,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final center = _selected ?? _fallbackCenter;
    final zoom = _selected == null ? 5.0 : 16.0;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Set location'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: InputDecoration(
                      hintText: 'Search by address',
                      prefixIcon: const Icon(Icons.search_rounded),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Search',
                  onPressed: _searching ? null : _search,
                  icon: _searching
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_forward_rounded),
                ),
              ],
            ),
          ),
          if (_results.isNotEmpty)
            SizedBox(
              height: 180,
              child: ListView.separated(
                itemCount: _results.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                itemBuilder: (context, index) {
                  final hit = _results[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.place_outlined),
                    title: Text(
                      hit.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _choose(hit),
                  );
                },
              ),
            ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: zoom,
                onTap: (_, point) {
                  setState(() {
                    _selected = point;
                    _selectedLabel = null;
                    _results = [];
                  });
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'xeebill_web',
                ),
                if (_selected != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _selected!,
                        width: 40,
                        height: 40,
                        alignment: Alignment.bottomCenter,
                        child: const Icon(
                          Icons.location_on,
                          color: Color(0xFFDC2626),
                          size: 40,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(
                        context,
                        const LocationMapResult(cleared: true),
                      ),
                      child: const Text('Clear pin'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      onPressed: _selected == null || _resolving
                          ? null
                          : _useSelected,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        foregroundColor: Colors.white,
                      ),
                      child: _resolving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Use this location'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
