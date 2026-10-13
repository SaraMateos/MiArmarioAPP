import 'advanced_data.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'models.dart';

class StylePreferences {
  final Map<String, int> garments, colors, categories;
  final Map<String, int> outfits;
  StylePreferences({
    Map<String, int>? garments,
    Map<String, int>? colors,
    Map<String, int>? categories,
    Map<String, int>? outfits,
  }) : garments = garments ?? {},
       colors = colors ?? {},
       categories = categories ?? {},
       outfits = outfits ?? {};
  factory StylePreferences.decode(String? value) {
    if (value == null) return StylePreferences();
    final m = jsonDecode(value) as Map;
    Map<String, int> read(String key) =>
        Map<String, int>.from(m[key] as Map? ?? {});
    return StylePreferences(
      garments: read('garments'),
      colors: read('colors'),
      categories: read('categories'),
      outfits: read('outfits'),
    );
  }
  String encode() => jsonEncode({
    'garments': garments,
    'colors': colors,
    'categories': categories,
    'outfits': outfits,
  });
  static String signature(Iterable<Garment> pieces) =>
      (pieces.map((g) => g.id).toList()..sort()).join('|');
  void rate(List<Garment> pieces, bool liked) {
    final delta = liked ? 1 : -1;
    void update(Map<String, int> values, String key) {
      values[key] = ((values[key] ?? 0) + delta).clamp(-5, 5);
    }

    for (final g in pieces) {
      update(garments, g.id);
    }
    for (final c in pieces.expand((g) => g.colorTags).toSet()) {
      update(colors, c);
    }
    for (final c in pieces.map((g) => g.category).toSet()) {
      update(categories, c);
    }
    outfits[signature(pieces)] = liked ? 1 : -1;
    // Bound storage while retaining the newest feedback.
    for (final values in [garments, colors, categories, outfits]) {
      while (values.length > 150) {
        values.remove(values.keys.first);
      }
    }
  }

  double score(Garment g) =>
      (garments[g.id] ?? 0) * 3.0 +
      g.colorTags.fold<double>(0, (n, c) => n + (colors[c] ?? 0)) /
          g.colorTags.length +
      (categories[g.category] ?? 0) * .3;
}

bool backupDue(
  Map<String, dynamic> reminder,
  DateTime now, {
  required bool hasData,
}) {
  if (!hasData || reminder['enabled'] == false) return false;
  final exported = DateTime.tryParse(reminder['last_export'] as String? ?? '');
  final snooze = DateTime.tryParse(reminder['snooze_until'] as String? ?? '');
  if (snooze != null && calendarDayDifference(now, snooze) < 0) return false;
  return exported == null || calendarDayDifference(now, exported) >= 7;
}

List<Garment> forgottenGarments(
  List<Garment> garments,
  Map<String, WearStat> usage,
  DateTime now, {
  int days = 30,
}) {
  final result = garments
      .where(
        (g) =>
            g.available &&
            (usage[g.id]?.lastWorn == null ||
                calendarDayDifference(now, usage[g.id]!.lastWorn!) >= days),
      )
      .toList();
  result.sort((a, b) {
    final ad = usage[a.id]?.lastWorn, bd = usage[b.id]?.lastWorn;
    if (ad == null && bd != null) return -1;
    if (bd == null && ad != null) return 1;
    return (ad?.compareTo(bd!) ?? 0) != 0
        ? ad!.compareTo(bd!)
        : a.name.compareTo(b.name);
  });
  return result;
}

class DuplicatePair {
  final Garment first, second;
  final int distance;
  DuplicatePair(this.first, this.second, this.distance);
}

class DuplicateService {
  static Future<String> fingerprint(String path) async {
    final codec = await ui.instantiateImageCodec(
      await File(path).readAsBytes(),
      targetWidth: 9,
      targetHeight: 8,
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw const FormatException('Foto ilegible.');
      final bytes = data.buffer.asUint8List();
      double luminance(int i) {
        final alpha = bytes[i + 3] / 255;
        return (bytes[i] * .299 + bytes[i + 1] * .587 + bytes[i + 2] * .114) *
                alpha +
            255 * (1 - alpha);
      }

      return [
        for (var y = 0; y < 8; y++)
          for (var x = 0; x < 8; x++)
            luminance((y * 9 + x) * 4) > luminance((y * 9 + x + 1) * 4)
                ? '1'
                : '0',
      ].join();
    } finally {
      image.dispose();
    }
  }

  static int distance(String a, String b) {
    if (a.length != 64 || b.length != 64) return 64;
    var count = 0;
    for (var i = 0; i < 64; i++) {
      if (a[i] != b[i]) count++;
    }
    return count;
  }

  static List<DuplicatePair> compare(
    List<Garment> pieces,
    Map<String, String> hashes,
  ) {
    final pairs = <DuplicatePair>[];
    for (var i = 0; i < pieces.length; i++) {
      for (var j = i + 1; j < pieces.length; j++) {
        final a = pieces[i],
            b = pieces[j],
            ha = hashes[a.id],
            hb = hashes[b.id];
        if (ha == null ||
            hb == null ||
            a.category != b.category ||
            !a.colorTags.any(b.colorTags.contains)) {
          continue;
        }
        // Flat images contain no useful shape information.
        if (!ha.contains('1') ||
            !ha.contains('0') ||
            !hb.contains('1') ||
            !hb.contains('0')) {
          continue;
        }
        final d = distance(ha, hb);
        if (d <= 5) pairs.add(DuplicatePair(a, b, d));
      }
    }
    pairs.sort((a, b) => a.distance.compareTo(b.distance));
    return pairs.take(min(100, pairs.length)).toList();
  }
}

class BrushStroke {
  final List<ui.Offset> points;
  final double radius;
  final bool restore;
  BrushStroke(this.points, this.radius, this.restore);
}

void paintCutout(
  ui.Canvas canvas,
  ui.Image current,
  ui.Image source,
  List<BrushStroke> strokes,
) {
  final bounds = ui.Rect.fromLTWH(
    0,
    0,
    current.width.toDouble(),
    current.height.toDouble(),
  );
  canvas.saveLayer(bounds, ui.Paint());
  canvas.drawImage(current, ui.Offset.zero, ui.Paint());
  for (final stroke in strokes) {
    final path = ui.Path();
    if (stroke.points.isEmpty) continue;
    path.moveTo(stroke.points.first.dx, stroke.points.first.dy);
    if (stroke.points.length == 1) {
      path.lineTo(stroke.points.first.dx + .01, stroke.points.first.dy);
    }
    for (final p in stroke.points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    final brush = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = stroke.radius * 2
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round;
    if (!stroke.restore) {
      canvas.drawPath(path, brush..blendMode = ui.BlendMode.clear);
    } else {
      canvas.saveLayer(bounds, ui.Paint());
      canvas.drawPath(path, brush);
      canvas.drawImageRect(
        source,
        ui.Rect.fromLTWH(
          0,
          0,
          source.width.toDouble(),
          source.height.toDouble(),
        ),
        bounds,
        ui.Paint()..blendMode = ui.BlendMode.srcIn,
      );
      canvas.restore();
    }
  }
  canvas.restore();
}

bool validToolSetting(String key, String value) {
  if ([
    'recommendation_profile',
    'linked_sets',
    'shopping',
    'usage_feedback',
  ].contains(key)) {
    return validAdvancedSetting(key, value);
  }
  try {
    final m = jsonDecode(value);
    if (m is! Map) return false;
    bool day(dynamic s, {bool empty = false}) =>
        s is String &&
        ((empty && s.isEmpty) ||
            (DateTime.tryParse(s) != null &&
                dateKey(DateTime.parse(s)) == s &&
                DateTime.parse(s).year >= 2020 &&
                DateTime.parse(s).year <= 2100));
    if (key == 'style_preferences') {
      if (m.length != 4 ||
          ![
            'garments',
            'colors',
            'categories',
            'outfits',
          ].every(m.containsKey)) {
        return false;
      }
      for (final v in m.values) {
        if (v is! Map || v.length > 150) return false;
        for (final e in v.entries) {
          if (e.key is! String ||
              (e.key as String).length > 2000 ||
              e.value is! int ||
              e.value < -5 ||
              e.value > 5) {
            return false;
          }
        }
      }
    } else if (key == 'backup_reminder') {
      if (!m.keys.every(['enabled', 'last_export', 'snooze_until'].contains)) {
        return false;
      }
      if (m.containsKey('enabled') && m['enabled'] is! bool) return false;
      for (final f in ['last_export', 'snooze_until']) {
        if (m.containsKey(f) && !day(m[f], empty: true)) return false;
      }
    } else if (key == 'suitcases') {
      if (m.length != 1 ||
          m['bags'] is! List ||
          (m['bags'] as List).length > 20) {
        return false;
      }
      final ids = <String>{};
      for (final b in m['bags']) {
        if (b is! Map ||
            b.length != 8 ||
            ![
              'id',
              'name',
              'start',
              'end',
              'items',
              'packed',
              'occasion',
              'climate',
            ].every(b.containsKey)) {
          return false;
        }
        if (b['id'] is! String ||
            b['id'].isEmpty ||
            b['id'].length > 200 ||
            !ids.add(b['id'])) {
          return false;
        }
        if (b['name'] is! String ||
            b['name'].trim().isEmpty ||
            b['name'].length > 100 ||
            !day(b['start']) ||
            !day(b['end']) ||
            b['start'].compareTo(b['end']) > 0) {
          return false;
        }
        if (!occasions.contains(b['occasion']) ||
            !['cold', 'mild', 'hot'].contains(b['climate'])) {
          return false;
        }
        for (final f in ['items', 'packed']) {
          final list = b[f];
          if (list is! List ||
              list.length > 300 ||
              list.any((v) => v is! String || v.isEmpty || v.length > 200) ||
              list.toSet().length != list.length) {
            return false;
          }
        }
        if ((b['items'] as List).isEmpty ||
            !(b['packed'] as List).every((b['items'] as List).contains)) {
          return false;
        }
      }
    }
    return true;
  } catch (_) {
    return false;
  }
}
