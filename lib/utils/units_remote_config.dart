import 'dart:convert';

import 'package:firebase_remote_config/firebase_remote_config.dart';

/// Fetches `units_json` from Firebase Remote Config and returns the decoded list.
///
/// Expects a JSON array of objects, e.g.
/// `[{"name":"Number","abbreviation":"nos","uom_type":"count"}, ...]`
Future<List<Map<String, dynamic>>> loadUnitsFromRemoteConfig() async {
  final remoteConfig = FirebaseRemoteConfig.instance;
  await remoteConfig.setConfigSettings(
    RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 10),
      minimumFetchInterval: const Duration(hours: 1),
    ),
  );
  await remoteConfig.fetchAndActivate();

  final jsonString = remoteConfig.getString('units_json');
  if (jsonString.isEmpty) {
    throw Exception('No units config found');
  }

  final decoded = jsonDecode(jsonString);
  if (decoded is! List) {
    throw Exception('units_json must be a JSON array');
  }

  return decoded
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
}
