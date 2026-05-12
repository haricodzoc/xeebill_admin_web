import 'dart:convert';

import '../models/item_model.dart';

/// Alphanumeric natural sort (e.g. uk1, uk2, uk10).
int naturalSortComparator(String a, String b) {
  final aChunks = _splitStringIntoChunks(a);
  final bChunks = _splitStringIntoChunks(b);
  final minLength = aChunks.length < bChunks.length ? aChunks.length : bChunks.length;

  for (var i = 0; i < minLength; i++) {
    final aChunk = aChunks[i];
    final bChunk = bChunks[i];
    if (aChunk is int && bChunk is int) {
      if (aChunk != bChunk) return aChunk.compareTo(bChunk);
    } else if (aChunk is String && bChunk is String) {
      final c = aChunk.toLowerCase().compareTo(bChunk.toLowerCase());
      if (c != 0) return c;
    } else if (aChunk is int && bChunk is String) {
      return -1;
    } else if (aChunk is String && bChunk is int) {
      return 1;
    }
  }
  return aChunks.length.compareTo(bChunks.length);
}

List<dynamic> _splitStringIntoChunks(String str) {
  final chunks = <dynamic>[];
  final currentChunk = StringBuffer();
  var isDigit = false;

  for (var i = 0; i < str.length; i++) {
    final char = str[i];
    final charIsDigit = RegExp(r'\d').hasMatch(char);

    if (i == 0) {
      isDigit = charIsDigit;
      currentChunk.write(char);
    } else {
      if (charIsDigit == isDigit) {
        currentChunk.write(char);
      } else {
        final chunkStr = currentChunk.toString();
        if (isDigit) {
          chunks.add(int.tryParse(chunkStr) ?? chunkStr);
        } else {
          chunks.add(chunkStr);
        }
        currentChunk.clear();
        currentChunk.write(char);
        isDigit = charIsDigit;
      }
    }
  }
  if (currentChunk.isNotEmpty) {
    final chunkStr = currentChunk.toString();
    if (isDigit) {
      chunks.add(int.tryParse(chunkStr) ?? chunkStr);
    } else {
      chunks.add(chunkStr);
    }
  }
  return chunks;
}

Map<String, dynamic> parseItemAttributesJson(ItemModel item) {
  if (item.attributes.isEmpty) return {};
  try {
    final decoded = jsonDecode(item.attributes);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {}
  return {};
}

/// Returns `true` if [item] satisfies all entries in [filters] given [attributeTypes].
/// Mirrors mobile `ItemsView` attribute filtering (select, multi-select, text, date range).
bool itemMatchesAttributeFilters(
  ItemModel item,
  Map<String, String> filters,
  Map<String, int> attributeTypes,
) {
  if (filters.isEmpty) return true;

  try {
    final itemAttributes = parseItemAttributesJson(item);

    final dateRangeFilters = <String, String>{};
    final regularFilters = <String, String>{};

    for (final e in filters.entries) {
      if (e.key.endsWith('_from') || e.key.endsWith('_to')) {
        dateRangeFilters[e.key] = e.value;
      } else {
        regularFilters[e.key] = e.value;
      }
    }

    for (final entry in regularFilters.entries) {
      final attrKey = entry.key;
      final selectedValue = entry.value;
      final attrType = attributeTypes[attrKey] ?? 1;

      if (!itemAttributes.containsKey(attrKey)) return false;

      final attrValue = itemAttributes[attrKey];
      var matches = false;

      if (attrValue is String) {
        if (attrType == 2) {
          final selectedValues = selectedValue.split(',').map((v) => v.trim()).toList();
          final itemValues = attrValue.split(',').map((v) => v.trim()).toList();
          matches = selectedValues.any(itemValues.contains);
        } else {
          matches = attrValue == selectedValue;
        }
      } else if (attrValue is Map) {
        if (attrValue.containsKey(selectedValue)) {
          final mapValue = attrValue[selectedValue];
          matches = mapValue == true || mapValue == 1 || mapValue == 'true';
        }
      }
      if (!matches) return false;
    }

    if (dateRangeFilters.isNotEmpty) {
      final dateRangesByAttr = <String, Map<String, String>>{};
      for (final entry in dateRangeFilters.entries) {
        final key = entry.key;
        late String baseAttrName;
        if (key.endsWith('_from')) {
          baseAttrName = key.substring(0, key.length - 5);
        } else {
          baseAttrName = key.substring(0, key.length - 3);
        }
        dateRangesByAttr.putIfAbsent(baseAttrName, () => {});
        dateRangesByAttr[baseAttrName]![key] = entry.value;
      }

      for (final dateRangeEntry in dateRangesByAttr.entries) {
        final baseAttrName = dateRangeEntry.key;
        final rangeFilters = dateRangeEntry.value;
        final fromDateStr = rangeFilters['${baseAttrName}_from'];
        final toDateStr = rangeFilters['${baseAttrName}_to'];

        if (!itemAttributes.containsKey(baseAttrName)) {
          if ((fromDateStr != null && fromDateStr.isNotEmpty) ||
              (toDateStr != null && toDateStr.isNotEmpty)) {
            return false;
          }
          continue;
        }

        final attrValue = itemAttributes[baseAttrName];
        if (attrValue is! String || attrValue.isEmpty) return false;

        try {
          var itemDate = DateTime.parse(attrValue);
          itemDate = DateTime(itemDate.year, itemDate.month, itemDate.day);
          var inRange = true;

          if (fromDateStr != null && fromDateStr.isNotEmpty) {
            var fromDate = DateTime.parse(fromDateStr);
            fromDate = DateTime(fromDate.year, fromDate.month, fromDate.day);
            if (itemDate.isBefore(fromDate)) inRange = false;
          }
          if (toDateStr != null && toDateStr.isNotEmpty) {
            var toDate = DateTime.parse(toDateStr);
            toDate = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59);
            if (itemDate.isAfter(toDate)) inRange = false;
          }
          if (!inRange) return false;
        } catch (_) {
          return false;
        }
      }
    }

    return true;
  } catch (e) {
    return true;
  }
}
