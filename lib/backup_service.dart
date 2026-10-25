import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'repository.dart';
import 'wardrobe_tools.dart';

class BackupService {
  final WardrobeRepository repo;
  BackupService(this.repo);
  static const maxZipBytes = 250 * 1024 * 1024;
  static const maxExpandedBytes = 500 * 1024 * 1024;
  Future<Uint8List> export() async {
    final data = await repo.snapshot();
    if (data.values.any((rows) => rows.length > 20000)) {
      throw const FormatException(
        'El armario supera los 20.000 registros por tabla admitidos en una copia.',
      );
    }
    final manifest = utf8.encode(
      jsonEncode({'format': 'mi_armario', 'version': 6, 'data': data}),
    );
    if (manifest.length > 8 * 1024 * 1024) {
      throw const FormatException(
        'Los datos del armario superan los 8 MB admitidos en una copia.',
      );
    }
    final archive = Archive()
      ..addFile(ArchiveFile('manifest.json', manifest.length, manifest));
    var total = manifest.length;
    for (final name in [
      ...data['garments']!.expand(
        (g) => [g['photo'] as String, g['source_photo'] as String],
      ),
      ...data['outfits']!.map((o) => o['reference_photo'] as String),
    ].where((n) => n.isNotEmpty).toSet()) {
      final file = File(repo.photoPath(name));
      if (!await file.exists()) {
        throw const FormatException(
          'Falta una foto. Revisa las prendas antes de exportar.',
        );
      }
      total += await file.length();
      if (total > maxExpandedBytes) {
        throw const FormatException(
          'El armario supera el límite de 500 MB por copia.',
        );
      }
      final bytes = await file.readAsBytes();
      archive.addFile(ArchiveFile('photos/$name', bytes.length, bytes));
    }
    final encoded = Uint8List.fromList(ZipEncoder().encode(archive));
    if (encoded.length > maxZipBytes) {
      throw const FormatException('La copia supera el límite de 250 MB.');
    }
    return encoded;
  }

  Future<void> restore(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > maxZipBytes) {
      throw const FormatException('El archivo está vacío o supera 250 MB.');
    }
    // Check original headers before the decoder merges duplicate names
    // or reads symbolic link payloads.
    final directory = ZipDirectory()..read(InputMemoryStream(bytes));
    var declaredTotal = 0;
    final names = <String>{};
    // Up to 20,000 garments can each retain a cutout and its original.
    if (directory.fileHeaders.length > 60001) {
      throw const FormatException('Demasiados archivos en la copia.');
    }
    for (final header in directory.fileHeaders) {
      declaredTotal += header.uncompressedSize;
      final type = (header.externalFileAttributes >> 16) & 0xf000;
      if (!names.add(header.filename) ||
          type == 0xa000 ||
          declaredTotal > maxExpandedBytes ||
          (header.filename != 'manifest.json' &&
              !RegExp(r'^photos/[a-zA-Z0-9_-]+\.(jpg|jpeg|png|webp)$')
                  .hasMatch(header.filename))) {
        throw const FormatException('Estructura ZIP no válida.');
      }
    }
    final archive = ZipDecoder().decodeBytes(bytes);
    var total = 0;
    final entries = <String, ArchiveFile>{};
    for (final file in archive) {
      total += file.size;
      if (total > maxExpandedBytes ||
          file.size < 0 ||
          entries.containsKey(file.name) ||
          !file.isFile ||
          file.isSymbolicLink) {
        throw const FormatException('Copia no válida o demasiado grande.');
      }
      if (file.name != 'manifest.json' &&
          !RegExp(r'^photos/[a-zA-Z0-9_-]+\.(jpg|jpeg|png|webp)$')
              .hasMatch(file.name)) {
        throw const FormatException('La copia contiene rutas no permitidas.');
      }
      entries[file.name] = file;
    }
    final manifest = entries['manifest.json'];
    if (manifest == null || manifest.size > 8 * 1024 * 1024) {
      throw const FormatException('No es una copia de Mi Armario.');
    }
    final decoded = jsonDecode(utf8.decode(readEntry(manifest)));
    final data = validateManifest(decoded);
    final photos = <String, String>{};
    final created = <File>[];
    try {
      for (final g in [...data['garments']!, ...data['outfits']!]) {
        for (final field
            in g.containsKey('photo')
                ? ['photo', 'source_photo']
                : ['reference_photo']) {
          final old = g[field] as String;
          if (old.isEmpty) continue;
          if (!photos.containsKey(old)) {
            final entry = entries['photos/$old'];
            if (entry == null || entry.size == 0) {
              throw const FormatException(
                'La copia está incompleta: falta una foto.',
              );
            }
            final newName =
                const Uuid().v4() + old.substring(old.lastIndexOf('.'));
            final file = File(repo.photoPath(newName));
            created.add(file);
            await file.writeAsBytes(readEntry(entry), flush: true);
            photos[old] = newName;
          }
          g[field] = photos[old];
        }
      }
      // Existing photos remain untouched until SQLite commits all rows.
      await repo.replaceData(data);
    } catch (_) {
      for (final file in created) {
        if (await file.exists()) {
          await file.delete();
        }
      }
      rethrow;
    }
  }

  static Uint8List readEntry(ArchiveFile entry) {
    final data = entry.content;
    if (data.length != entry.size || getCrc32(data) != entry.crc32) {
      throw const FormatException('La copia contiene un archivo dañado.');
    }
    return data;
  }

  static Map<String, List<Map<String, Object?>>> validateManifest(
    Object? decoded,
  ) {
    Never invalid() =>
        throw const FormatException('Los datos de la copia no son válidos.');
    if (decoded is! Map ||
        decoded['format'] != 'mi_armario' ||
        ![1, 2, 3, 4, 5, 6].contains(decoded['version']) ||
        decoded['data'] is! Map) {
      invalid();
    }
    final version = decoded['version'] as int;
    final raw = decoded['data'] as Map;
    final result = <String, List<Map<String, Object?>>>{};
    final columns = {
      'garments': [
        'id',
        'name',
        'category',
        'color',
        'season',
        'occasion',
        'notes',
        'photo',
        'favorite',
        if (version >= 2) 'warmth',
        if (version >= 3) 'status',
        if (version >= 3) 'source_photo',
        if (version >= 4) 'subtype',
        if (version >= 5) 'details',
      ],
      'outfits': [
        'id',
        'name',
        'occasion',
        'notes',
        'favorite',
        if (version >= 5) 'reference_photo',
      ],
      'outfit_items': [
        'outfit_id',
        'garment_id',
        'position',
        'x',
        'y',
        'scale',
        if (version >= 6) 'mannequin_x',
        if (version >= 6) 'mannequin_y',
        if (version >= 6) 'mannequin_scale',
      ],
      'plans': ['date', 'outfit_id', 'worn'],
      'garment_wears': ['date', 'garment_id'],
      'settings': ['key', 'value'],
    };
    bool validDay(Object? value) {
      if (value is! String) return false;
      final d = DateTime.tryParse(value);
      return d != null &&
          d.year >= 2020 &&
          d.year <= 2100 &&
          dateKey(d) == value;
    }

    for (final table in WardrobeRepository.tables) {
      final rows = version == 1 && ['garment_wears', 'settings'].contains(table)
          ? []
          : raw[table];
      if (rows is! List || rows.length > 20000) invalid();
      result[table] = [];
      for (final row in rows) {
        if (row is! Map ||
            row.length != columns[table]!.length ||
            !columns[table]!.every(row.containsKey)) {
          invalid();
        }
        final m = Map<String, Object?>.from(row);
        if (table == 'outfit_items' && version < 6) {
          m['mannequin_x'] = .3;
          m['mannequin_y'] = .2;
          m['mannequin_scale'] = 1.0;
        }
        for (final key in columns[table]!) {
          final v = m[key];
          if (['favorite', 'worn'].contains(key)) {
            if (v != 0 && v != 1) invalid();
          } else if (key == 'warmth') {
            if (v is! int || v < 1 || v > 3) invalid();
          } else if (key == 'position') {
            if (v is! int || v < 0 || v > 30) invalid();
          } else if (['x', 'y', 'scale', 'mannequin_x', 'mannequin_y', 'mannequin_scale'].contains(key)) {
            if (v is! num ||
                !v.isFinite ||
                (key == 'scale' || key == 'mannequin_scale' ? v < .5 || v > 1.8 : v < 0 || v > 1)) {
              invalid();
            }
          } else {
            final maxLength = key == 'value'
                ? 500000
                : [
                    'notes',
                    'color',
                    'season',
                    'occasion',
                    'details',
                  ].contains(key)
                ? 2000
                : 200;
            if (v is! String || v.length > maxLength) invalid();
          }
        }
        if (m.containsKey('name') && (m['name'] as String).trim().isEmpty) {
          invalid();
        }
        if (m.containsKey('id') && (m['id'] as String).isEmpty) invalid();
        if (m.containsKey('date') && !validDay(m['date'])) invalid();
        if (table == 'garments') {
          if (!categories.contains(m['category']) ||
              !validSelections(m['color'], colors) ||
              !validSelections(m['season'], seasons) ||
              !validSelections(m['occasion'], occasions) ||
              !RegExp(r'^[a-zA-Z0-9_-]+\.(jpg|jpeg|png|webp)$')
                  .hasMatch(m['photo'] as String)) {
            invalid();
          }
          for (final field in ['color', 'season', 'occasion']) {
            m[field] = jsonEncode(readSelections(m[field]));
          }
          if (version < 5) m['details'] = '{}';
          try {
            if (!validGarmentDetails(jsonDecode(m['details'] as String))) {
              invalid();
            }
          } catch (_) {
            invalid();
          }
          if (version < 4) m['subtype'] = '';
          if (m['subtype'] != '' && !garmentTypes.containsKey(m['subtype'])) {
            invalid();
          }
          if (m['subtype'] != '') m['category'] = garmentTypes[m['subtype']];
          if (version == 1) m['warmth'] = 2;
          if (version < 3) {
            m['status'] = 'Disponible';
            m['source_photo'] = '';
          }
          if (!garmentStates.contains(m['status']) ||
              (m['source_photo'] != '' &&
                  !RegExp(r'^[a-zA-Z0-9_-]+\.(jpg|jpeg|png|webp)$')
                      .hasMatch(m['source_photo'] as String))) {
            invalid();
          }
        }
        if (table == 'outfits') {
          if (version < 5) m['reference_photo'] = '';
          if (m['reference_photo'] != '' &&
              !RegExp(r'^[a-zA-Z0-9_-]+\.(jpg|jpeg|png|webp)$')
                  .hasMatch(m['reference_photo'] as String)) {
            invalid();
          }
          if (!validSelections(m['occasion'], occasions)) invalid();
          m['occasion'] = jsonEncode(readSelections(m['occasion']));
        }
        if (table == 'settings') {
          if (![
            'climate',
            'weather_cache',
            'style_preferences',
            'suitcases',
            'backup_reminder',
            'recommendation_profile',
            'linked_sets',
            'shopping',
            'usage_feedback',
          ].contains(m['key'])) {
            invalid();
          }
          try {
            if (!validToolSetting(m['key'] as String, m['value'] as String)) {
              invalid();
            }
          } catch (_) {
            invalid();
          }
        }
        result[table]!.add(m);
      }
    }
    final garments = result['garments']!.map((r) => r['id']).toSet();
    final outfits = result['outfits']!.map((r) => r['id']).toSet();
    if (garments.length != result['garments']!.length ||
        outfits.length != result['outfits']!.length) {
      invalid();
    }
    final pairs = <String>{};
    for (final r in result['outfit_items']!) {
      if (!garments.contains(r['garment_id']) ||
          !outfits.contains(r['outfit_id']) ||
          !pairs.add(jsonEncode([r['outfit_id'], r['garment_id']]))) {
        invalid();
      }
    }
    for (final id in outfits) {
      final count = result['outfit_items']!
          .where((i) => i['outfit_id'] == id)
          .length;
      if (count == 0 || count > 30) invalid();
    }
    final dates = <Object?>{};
    for (final r in result['plans']!) {
      if (!outfits.contains(r['outfit_id']) || !dates.add(r['date'])) invalid();
    }
    if (version == 1) {
      for (final p in result['plans']!.where((p) => p['worn'] == 1)) {
        for (final i in result['outfit_items']!.where(
          (i) => i['outfit_id'] == p['outfit_id'],
        )) {
          result['garment_wears']!.add({
            'date': p['date'],
            'garment_id': i['garment_id'],
          });
        }
      }
    }
    final usedDays = result['plans']!
        .where((p) => p['worn'] == 1)
        .map((p) => p['date'])
        .toSet();
    final wearPairs = <String>{};
    for (final r in result['garment_wears']!) {
      if (!garments.contains(r['garment_id']) ||
          !usedDays.contains(r['date']) ||
          !wearPairs.add(jsonEncode([r['date'], r['garment_id']]))) {
        invalid();
      }
    }
    final keys = result['settings']!.map((r) => r['key']).toSet();
    if (keys.length != result['settings']!.length ||
        result['garment_wears']!.length > 20000) {
      invalid();
    }
    return result;
  }
}
