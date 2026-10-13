import 'dart:convert';

import 'models.dart';

class RecommendationProfile {
  String style;
  bool rain, wind;
  Map<String, List<String>> exclusions;
  List<List<String>> linkedSets;
  RecommendationProfile({
    this.style = 'Sin preferencia',
    this.rain = false,
    this.wind = false,
    Map<String, List<String>>? exclusions,
    this.linkedSets = const [],
  }) : exclusions = exclusions ?? {};
  Set<String> excludedOn(DateTime day) =>
      (exclusions[dateKey(day)] ?? []).toSet();
  String encode() => jsonEncode({
    'style': style,
    'rain': rain,
    'wind': wind,
    'exclusions': exclusions,
  });
  static RecommendationProfile decode(String? value) {
    try {
      if (value == null ||
          !validAdvancedSetting('recommendation_profile', value)) {
        return RecommendationProfile();
      }
      final m = jsonDecode(value) as Map;
      return RecommendationProfile(
        style: m['style'] as String,
        rain: m['rain'] as bool,
        wind: m['wind'] as bool,
        exclusions: {
          for (final e in (m['exclusions'] as Map).entries)
            e.key as String: (e.value as List).cast<String>(),
        },
      );
    } catch (_) {
      return RecommendationProfile();
    }
  }
}

List<Map<String, dynamic>> readEntries(String? value) {
  try {
    return (jsonDecode(value ?? '{"entries":[]}')['entries'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  } catch (_) {
    return [];
  }
}

String writeEntries(List<Map<String, dynamic>> entries) =>
    jsonEncode({'entries': entries});
bool validAdvancedSetting(String key, String value) {
  try {
    final m = jsonDecode(value);
    if (m is! Map) return false;
    bool text(dynamic v, int max) => v is String && v.length <= max;
    bool ids(dynamic v, int max) =>
        v is List &&
        v.length <= max &&
        v.toSet().length == v.length &&
        v.every((x) => text(x, 200) && x.isNotEmpty);
    bool day(dynamic v) =>
        v is String &&
        DateTime.tryParse(v) != null &&
        dateKey(DateTime.parse(v)) == v &&
        DateTime.parse(v).year >= 2020 &&
        DateTime.parse(v).year <= 2100;
    if (key == 'recommendation_profile') {
      if (m.length != 4 ||
          !outfitStyles.contains(m['style']) ||
          m['rain'] is! bool ||
          m['wind'] is! bool ||
          m['exclusions'] is! Map ||
          m['exclusions'].length > 30) {
        return false;
      }
      return (m['exclusions'] as Map).entries.every(
        (e) => day(e.key) && ids(e.value, 300),
      );
    }
    if (m.length != 1 || m['entries'] is! List || m['entries'].length > 150) {
      return false;
    }
    final seen = <String>{};
    for (final e in m['entries']) {
      if (e is! Map ||
          !text(e['id'], 200) ||
          e['id'].isEmpty ||
          !seen.add(e['id'] as String)) {
        return false;
      }
      if (key == 'linked_sets') {
        if (e.length != 3 ||
            !text(e['name'], 100) ||
            e['name'].trim().isEmpty ||
            !ids(e['items'], 10) ||
            e['items'].length < 2) {
          return false;
        }
      } else if (key == 'shopping') {
        if (e.length != 5 ||
            !text(e['name'], 100) ||
            e['name'].trim().isEmpty ||
            !categories.contains(e['category']) ||
            !colors.contains(e['color']) ||
            !text(e['notes'], 300)) {
          return false;
        }
      } else if (key == 'usage_feedback') {
        if (e.length != 5 ||
            !day(e['id']) ||
            !text(e['outfit_id'], 200) ||
            !ids(e['items'], 30) ||
            ![
              'Cómodo',
              'Pasé frío',
              'Demasiado abrigado',
              'No me convenció',
            ].contains(e['rating']) ||
            !text(e['notes'], 300)) {
          return false;
        }
      } else {
        return false;
      }
    }
    return true;
  } catch (_) {
    return false;
  }
}
