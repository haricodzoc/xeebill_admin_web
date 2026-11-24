import 'dart:convert';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

import 'constants.dart';

/// Merges `below_one` from the built-in [UNITS] defaults when Remote Config omits it.
List<Map<String, dynamic>> mergeUnitBelowOneFromDefaults(
  List<Map<String, dynamic>> units,
) {
  final defaultsByKey = <String, Map<String, dynamic>>{};
  for (final u in UNITS) {
    final belowOne = u['below_one'];
    if (belowOne is! Map) continue;
    final ab = u['abbreviation']?.toString().toLowerCase() ?? '';
    final nm = u['name']?.toString().toLowerCase() ?? '';
    if (ab.isNotEmpty) {
      defaultsByKey[ab] = Map<String, dynamic>.from(belowOne);
    }
    if (nm.isNotEmpty) {
      defaultsByKey[nm] = Map<String, dynamic>.from(belowOne);
    }
  }

  return units.map((unit) {
    if (unit['below_one'] != null) return unit;
    final ab = unit['abbreviation']?.toString().toLowerCase() ?? '';
    final nm = unit['name']?.toString().toLowerCase() ?? '';
    final belowOne = defaultsByKey[ab] ?? defaultsByKey[nm];
    if (belowOne == null) return unit;
    return {...unit, 'below_one': Map<String, dynamic>.from(belowOne)};
  }).toList();
}

String _defaultUnitsJson() => jsonEncode(UNITS);

/// Fetches `units_json` from Firebase Remote Config (same key as the mobile app).
Future<List<Map<String, dynamic>>> loadUnitsFromRemoteConfig() async {
  final remoteConfig = FirebaseRemoteConfig.instance;
  await remoteConfig.setConfigSettings(
    RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 10),
      // Web / admin: allow a fresh fetch each session so units stay current.
      minimumFetchInterval: kIsWeb
          ? Duration.zero
          : const Duration(hours: 1),
    ),
  );
  await remoteConfig.setDefaults(<String, dynamic>{
    'units_json': _defaultUnitsJson(),
  });
  await remoteConfig.fetchAndActivate();

  final jsonString = remoteConfig.getString('units_json');
  if (jsonString.isEmpty) {
    throw Exception('No units config found');
  }

  final decoded = jsonDecode(jsonString);
  if (decoded is! List) {
    throw Exception('units_json must be a JSON array');
  }

  final parsed = decoded
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .where((m) => (m['name']?.toString().trim() ?? '').isNotEmpty)
      .toList();

  if (parsed.isEmpty) {
    throw Exception('units_json contained no valid units');
  }

  return mergeUnitBelowOneFromDefaults(parsed);
}

bool _unitsLoadAttempted = false;

/// Loads Remote Config units into [UNITS] once (safe to call from screens).
Future<void> ensureUnitsLoaded({bool force = false}) async {
  if (_unitsLoadAttempted && !force) return;
  _unitsLoadAttempted = true;
  try {
    final units = await loadUnitsFromRemoteConfig();
    UNITS = units;
    sortUnitsAlphabetically();
    debugPrint('Units: loaded ${UNITS.length} from Remote Config');
  } catch (e, st) {
    debugPrint('Units: using defaults (remote config failed): $e');
    debugPrint('$st');
    sortUnitsAlphabetically();
  }
}
