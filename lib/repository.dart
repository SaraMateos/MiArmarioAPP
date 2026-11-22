import 'advanced_data.dart';

import 'dart:io';
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

class WardrobeRepository {
  final Directory root;
  final Database db;
  WardrobeRepository._(this.root, this.db);
  static const tables = [
    'garments',
    'outfits',
    'outfit_items',
    'plans',
    'garment_wears',
    'settings',
  ];
  static Future<WardrobeRepository> open(Directory root) async {
    await root.create(recursive: true);
    await Directory(p.join(root.path, 'photos')).create(recursive: true);
    final db = await openDatabase(
      p.join(root.path, 'wardrobe.db'),
      version: 7,
      onOpen: (db) async {
        await db.execute(
          "CREATE TABLE IF NOT EXISTS undo_actions(id INTEGER PRIMARY KEY AUTOINCREMENT, label TEXT NOT NULL, data TEXT NOT NULL)",
        );
      },
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE garments(id TEXT PRIMARY KEY, name TEXT NOT NULL, category TEXT NOT NULL, color TEXT NOT NULL, season TEXT NOT NULL, occasion TEXT NOT NULL, notes TEXT NOT NULL, photo TEXT NOT NULL, subtype TEXT NOT NULL DEFAULT \'\', status TEXT NOT NULL DEFAULT \'Disponible\', source_photo TEXT NOT NULL DEFAULT \'\', warmth INTEGER NOT NULL DEFAULT 2 CHECK(warmth BETWEEN 1 AND 3), favorite INTEGER NOT NULL CHECK(favorite IN (0,1)))',
        );
        await db.execute(
          'CREATE TABLE outfits(id TEXT PRIMARY KEY, name TEXT NOT NULL, occasion TEXT NOT NULL, notes TEXT NOT NULL, favorite INTEGER NOT NULL CHECK(favorite IN (0,1)))',
        );
        await db.execute(
          'CREATE TABLE outfit_items(outfit_id TEXT NOT NULL REFERENCES outfits(id) ON DELETE CASCADE, garment_id TEXT NOT NULL REFERENCES garments(id) ON DELETE RESTRICT, position INTEGER NOT NULL, x REAL NOT NULL, y REAL NOT NULL, scale REAL NOT NULL, mannequin_x REAL NOT NULL DEFAULT -1.0, mannequin_y REAL NOT NULL DEFAULT 0.2, mannequin_scale REAL NOT NULL DEFAULT 1.0, PRIMARY KEY(outfit_id, garment_id))',
        );
        await db.execute(
          'CREATE TABLE plans(date TEXT PRIMARY KEY, outfit_id TEXT NOT NULL REFERENCES outfits(id) ON DELETE CASCADE, worn INTEGER NOT NULL CHECK(worn IN (0,1)))',
        );
        await db.execute(
          'CREATE INDEX idx_outfit_items_garment ON outfit_items(garment_id)',
        );
        await createNewTables(db);
        await db.execute(
          "ALTER TABLE garments ADD COLUMN details TEXT NOT NULL DEFAULT '{}'",
        );
        await db.execute(
          "ALTER TABLE outfits ADD COLUMN reference_photo TEXT NOT NULL DEFAULT ''",
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE garments ADD COLUMN warmth INTEGER NOT NULL DEFAULT 2',
          );
          for (final table in ['garments', 'outfits']) {
            for (final row in await db.query(table)) {
              final fields = table == 'garments'
                  ? ['color', 'season', 'occasion']
                  : ['occasion'];
              await db.update(
                table,
                {for (final f in fields) f: jsonEncode(readSelections(row[f]))},
                where: 'id = ?',
                whereArgs: [row['id']],
              );
            }
          }
          await createNewTables(db);
          await db.execute(
            'INSERT OR IGNORE INTO garment_wears(date, garment_id) SELECT plans.date, outfit_items.garment_id FROM plans JOIN outfit_items ON plans.outfit_id = outfit_items.outfit_id WHERE plans.worn = 1',
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            "ALTER TABLE garments ADD COLUMN status TEXT NOT NULL DEFAULT 'Disponible'",
          );
          await db.execute(
            "ALTER TABLE garments ADD COLUMN source_photo TEXT NOT NULL DEFAULT ''",
          );
        }
        if (oldVersion < 4) {
          await db.execute(
            "ALTER TABLE garments ADD COLUMN subtype TEXT NOT NULL DEFAULT ''",
          );
        }
        if (oldVersion < 6) {
          await db.execute(
            'ALTER TABLE outfit_items ADD COLUMN mannequin_x REAL NOT NULL DEFAULT -1.0',
          );
          await db.execute(
            'ALTER TABLE outfit_items ADD COLUMN mannequin_y REAL NOT NULL DEFAULT 0.2',
          );
          await db.execute(
            'ALTER TABLE outfit_items ADD COLUMN mannequin_scale REAL NOT NULL DEFAULT 1.0',
          );
        }
        if (oldVersion == 6) {
          // Only reset outfits whose entire mannequin still has the v6 defaults.
          await db.execute("""
            UPDATE outfit_items SET mannequin_x = -1.0
            WHERE outfit_id NOT IN (
              SELECT outfit_id FROM outfit_items
              WHERE mannequin_x != 0.3 OR mannequin_y != 0.2 OR mannequin_scale != 1.0
            )
          """);
        }
        if (oldVersion < 5) {
          await db.execute(
            "ALTER TABLE garments ADD COLUMN details TEXT NOT NULL DEFAULT '{}'",
          );
          await db.execute(
            "ALTER TABLE outfits ADD COLUMN reference_photo TEXT NOT NULL DEFAULT ''",
          );
        }
      },
    );
    return WardrobeRepository._(root, db);
  }

  static Future<void> createNewTables(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE garment_wears(date TEXT NOT NULL, garment_id TEXT NOT NULL REFERENCES garments(id) ON DELETE CASCADE, PRIMARY KEY(date, garment_id))',
    );
    await db.execute(
      'CREATE INDEX idx_garment_wears_id ON garment_wears(garment_id, date)',
    );
    await db.execute(
      'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
  }

  Future<Map<String, WearStat>> usageStats({DateTime? until}) async {
    final rows = await db.rawQuery(
      'SELECT garment_id, COUNT(*) AS count, MAX(date) AS last FROM garment_wears WHERE date <= ? GROUP BY garment_id',
      [dateKey(until ?? DateTime.now())],
    );
    return {
      for (final r in rows)
        r['garment_id'] as String: WearStat(
          count: r['count'] as int,
          lastWorn: DateTime.parse(r['last'] as String),
        ),
    };
  }

  Future<String?> setting(String key) async {
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> saveSetting(String key, String value) async {
    if ([
          'recommendation_profile',
          'linked_sets',
          'shopping',
          'usage_feedback',
        ].contains(key) &&
        !validAdvancedSetting(key, value)) {
      throw const FormatException('Revisa los datos de la herramienta.');
    }
    await db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  String photoPath(String name) => p.join(root.path, 'photos', name);
  Future<String> importPhoto(String source) async {
    final ext = p.extension(source).toLowerCase();
    final filename =
        const Uuid().v4() +
        (['.jpg', '.jpeg', '.png', '.webp'].contains(ext) ? ext : '.jpg');
    await File(source).copy(photoPath(filename));
    return filename;
  }

  Future<List<Garment>> garments() async => (await db.query(
    'garments',
    orderBy: 'favorite DESC, name COLLATE NOCASE',
  )).map(Garment.fromMap).toList();
  Future<List<Outfit>> outfits() async {
    final rows = await db.query(
      'outfits',
      orderBy: 'favorite DESC, name COLLATE NOCASE',
    );
    final items = await db.query('outfit_items', orderBy: 'position');
    return rows
        .map(
          (m) => Outfit(
            id: m['id'] as String,
            name: m['name'] as String,
            occasionTags: readSelections(m['occasion']),
            notes: m['notes'] as String,
            referencePhoto: m['reference_photo'] as String? ?? '',
            favorite: m['favorite'] == 1,
            items: items
                .where((i) => i['outfit_id'] == m['id'])
                .map(OutfitItem.fromMap)
                .toList(),
          ),
        )
        .toList();
  }

  Future<List<DayPlan>> plans() async =>
      (await db.query('plans', orderBy: 'date DESC'))
          .map(
            (m) => DayPlan(
              m['date'] as String,
              m['outfit_id'] as String,
              m['worn'] == 1,
            ),
          )
          .toList();
  Future<void> saveGarment(Garment g) async {
    if (g.name.trim().isEmpty || !File(photoPath(g.photo)).existsSync()) {
      throw const FormatException('La prenda necesita nombre y foto.');
    }
    if (!validGarmentDetails(g.details) ||
        (g.subtype.isNotEmpty && !garmentTypes.containsKey(g.subtype)) ||
        !categories.contains(g.category) ||
        !validSelections(g.colorTags, colors) ||
        !validSelections(g.seasonTags, seasons) ||
        !validSelections(g.occasionTags, occasions) ||
        g.warmth < 1 ||
        g.warmth > 3 ||
        !garmentStates.contains(g.status) ||
        (g.sourcePhoto.isNotEmpty &&
            !File(photoPath(g.sourcePhoto)).existsSync())) {
      throw const FormatException('Revisa los datos de la prenda.');
    }
    final previous = await db.query(
      'garments',
      where: 'id = ?',
      whereArgs: [g.id],
    );
    await db.transaction((tx) async {
      if (previous.isEmpty) {
        await tx.insert('garments', g.toMap());
      } else {
        await tx.update(
          'garments',
          g.toMap(),
          where: 'id = ?',
          whereArgs: [g.id],
        );
      }
      if (previous.isNotEmpty &&
          previous.first['status'] != g.status &&
          _canonical({...previous.first, 'status': g.status}) ==
              _canonical(g.toMap())) {
        await _recordUndo(
          tx,
          'Cambiar disponibilidad · ${g.name}',
          'garments',
          [g.id],
          previous,
          await _garmentState(tx, {g.id}),
        );
      }
    });
    if (previous.isNotEmpty && previous.first['photo'] != g.photo) {
      try {
        await cleanupPhotos();
      } on FileSystemException {
        /* retry later */
      }
    }
  }

  Future<void> batchUpdate(
    Set<String> ids,
    Map<String, Object?> changes,
  ) async {
    if (ids.isEmpty ||
        !changes.keys.every(
          ['subtype', 'category', 'status', 'season'].contains,
        )) {
      throw const FormatException('Selección no válida.');
    }
    final fields = {...changes};
    if (fields.containsKey('season')) {
      if (!validSelections(fields['season'], seasons)) {
        throw const FormatException('Temporadas no válidas.');
      }
      fields['season'] = jsonEncode(fields['season']);
    }
    if ((fields.containsKey('status') &&
            !garmentStates.contains(fields['status'])) ||
        (fields.containsKey('subtype') &&
            !garmentTypes.containsKey(fields['subtype']))) {
      throw const FormatException('Tipo o disponibilidad no válidos.');
    }
    if (fields.containsKey('subtype')) {
      fields['category'] = garmentTypes[fields['subtype']];
    }
    if (fields.containsKey('category') &&
        !categories.contains(fields['category'])) {
      throw const FormatException('Categoría no válida.');
    }
    await db.transaction((tx) async {
      final beforeUndo = await _garmentState(tx, ids);
      for (final id in ids) {
        if ((await tx.query(
          'garments',
          where: 'id = ?',
          whereArgs: [id],
        )).isEmpty) {
          throw const FormatException('Una prenda ya no existe.');
        }
        final updateFields = {...fields};
        if (fields.containsKey('subtype')) {
          final current = await tx.query(
            'garments',
            where: 'id = ?',
            whereArgs: [id],
          );
          final details = Map<String, Object?>.from(
            jsonDecode(current.single['details'] as String) as Map,
          );
          details['needs_review'] = false;
          if (details.containsKey('type_review')) {
            details['type_review'] = false;
          }
          updateFields['details'] = jsonEncode(details);
        }
        await tx.update(
          'garments',
          updateFields,
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      await _recordUndo(
        tx,
        'Editar disponibilidad o lote',
        'garments',
        ids.toList()..sort(),
        beforeUndo,
        await _garmentState(tx, ids),
      );
    });
  }

  Future<void> favorite(String table, String id, bool value) async {
    if (!['garments', 'outfits'].contains(table)) {
      throw ArgumentError('Tabla incorrecta');
    }
    await db.update(
      table,
      {'favorite': value ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> garmentUsage(String id) async =>
      Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM outfit_items WHERE garment_id = ?',
          [id],
        ),
      ) ??
      0;
  Future<void> deleteGarment(String id) async {
    if (await garmentUsage(id) > 0) {
      throw const FormatException(
        'Quita la prenda de sus outfits antes de borrarla.',
      );
    }
    await db.delete('garments', where: 'id = ?', whereArgs: [id]);
    try {
      await cleanupPhotos();
    } on FileSystemException {
      /* retry later */
    }
  }

  Future<void> saveOutfit(Outfit o) async {
    if (o.name.trim().isEmpty || o.items.isEmpty) {
      throw const FormatException('Añade un nombre y al menos una prenda.');
    }
    if ((o.referencePhoto.isNotEmpty &&
            !File(photoPath(o.referencePhoto)).existsSync()) ||
        !validSelections(o.occasionTags, occasions) ||
        o.items.length > 30 ||
        o.items.map((i) => i.garmentId).toSet().length != o.items.length) {
      throw const FormatException('Revisa las prendas y ocasiones del outfit.');
    }
    await db.transaction((tx) async {
      final exists = await tx.query(
        'outfits',
        where: 'id = ?',
        whereArgs: [o.id],
      );
      if (exists.isEmpty) {
        await tx.insert('outfits', o.toMap());
      } else {
        await tx.update(
          'outfits',
          o.toMap(),
          where: 'id = ?',
          whereArgs: [o.id],
        );
      }
      await tx.delete(
        'outfit_items',
        where: 'outfit_id = ?',
        whereArgs: [o.id],
      );
      for (var i = 0; i < o.items.length; i++) {
        await tx.insert('outfit_items', o.items[i].toMap(o.id, i));
      }
    });
    try {
      await cleanupPhotos();
    } on FileSystemException {
      /* retry later */
    }
  }

  Future<void> deleteOutfit(String id) async {
    await db.transaction((tx) async {
      final feedback = await tx.query(
        'settings',
        where: 'key = ?',
        whereArgs: ['usage_feedback'],
      );
      if (feedback.isNotEmpty) {
        final entries = readEntries(feedback.first['value'] as String)
          ..removeWhere((e) => e['outfit_id'] == id);
        await tx.update(
          'settings',
          {'value': writeEntries(entries)},
          where: 'key = ?',
          whereArgs: ['usage_feedback'],
        );
      }
      await tx.rawDelete(
        'DELETE FROM garment_wears WHERE date IN (SELECT date FROM plans WHERE outfit_id = ?)',
        [id],
      );
      await tx.delete('outfits', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> savePlan(DayPlan plan) async {
    final day = DateTime.tryParse(plan.date);
    if (day == null ||
        dateKey(day) != plan.date ||
        day.year < 2020 ||
        day.year > 2100 ||
        (plan.worn && plan.date.compareTo(dateKey(DateTime.now())) > 0)) {
      throw const FormatException(
        'La fecha o el registro de uso no es válido.',
      );
    }
    await db.transaction((tx) async {
      final beforeUndo = await _planState(tx, plan.date);
      final previous = await tx.query(
        'plans',
        where: 'date = ?',
        whereArgs: [plan.date],
      );
      final keepWear =
          plan.worn &&
          previous.isNotEmpty &&
          previous.first['worn'] == 1 &&
          previous.first['outfit_id'] == plan.outfitId;
      await tx.insert(
        'plans',
        plan.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (!keepWear) {
        final savedFeedback = await tx.query(
          'settings',
          where: 'key = ?',
          whereArgs: ['usage_feedback'],
        );
        if (savedFeedback.isNotEmpty) {
          final entries = readEntries(savedFeedback.first['value'] as String)
            ..removeWhere((e) => e['id'] == plan.date);
          await tx.update(
            'settings',
            {'value': writeEntries(entries)},
            where: 'key = ?',
            whereArgs: ['usage_feedback'],
          );
        }
        await tx.delete(
          'garment_wears',
          where: 'date = ?',
          whereArgs: [plan.date],
        );
        if (plan.worn) {
          final items = await tx.query(
            'outfit_items',
            where: 'outfit_id = ?',
            whereArgs: [plan.outfitId],
          );
          for (final item in items) {
            await tx.insert('garment_wears', {
              'date': plan.date,
              'garment_id': item['garment_id'],
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }
      }
      await _recordUndo(
        tx,
        'Cambiar calendario · ${plan.date}',
        'plan',
        plan.date,
        beforeUndo,
        await _planState(tx, plan.date),
      );
    });
  }

  Future<void> saveNewWeek(Map<DayPlan, Outfit> entries) async {
    final dates = entries.keys.map((p) => p.date).toSet();
    if (dates.length != entries.length) {
      throw const FormatException('Hay días duplicados.');
    }
    await db.transaction((tx) async {
      final undoDates = entries.keys.map((e) => e.date).toList()..sort();
      final beforeUndo = {
        for (final day in undoDates) day: await _planState(tx, day),
      };
      for (final e in entries.entries) {
        final day = DateTime.tryParse(e.key.date);
        if (day == null ||
            dateKey(day) != e.key.date ||
            day.year < 2020 ||
            day.year > 2100 ||
            e.value.items.length > 30 ||
            e.value.items.map((i) => i.garmentId).toSet().length !=
                e.value.items.length) {
          throw const FormatException('Plan no válido.');
        }
        if (e.key.outfitId != e.value.id ||
            e.key.worn ||
            e.value.items.isEmpty ||
            !validSelections(e.value.occasionTags, occasions)) {
          throw const FormatException('Plan no válido.');
        }
        if ((await tx.query(
          'plans',
          where: 'date = ?',
          whereArgs: [e.key.date],
        )).isNotEmpty) {
          throw const FormatException(
            'Uno de los días ya está planificado. Regenera la propuesta.',
          );
        }
        await tx.insert('outfits', e.value.toMap());
        for (var i = 0; i < e.value.items.length; i++) {
          await tx.insert(
            'outfit_items',
            e.value.items[i].toMap(e.value.id, i),
          );
        }
        await tx.insert('plans', e.key.toMap());
      }
      await _recordUndo(
        tx,
        'Planificar semana',
        'week',
        undoDates,
        beforeUndo,
        {for (final day in undoDates) day: await _planState(tx, day)},
      );
    });
  }

  Future<void> deletePlan(String date) async {
    await db.transaction((tx) async {
      final beforeUndo = await _planState(tx, date);
      final feedback = await tx.query(
        'settings',
        where: 'key = ?',
        whereArgs: ['usage_feedback'],
      );
      if (feedback.isNotEmpty) {
        final entries = readEntries(feedback.first['value'] as String)
          ..removeWhere((e) => e['id'] == date);
        await tx.update(
          'settings',
          {'value': writeEntries(entries)},
          where: 'key = ?',
          whereArgs: ['usage_feedback'],
        );
      }
      await tx.delete('garment_wears', where: 'date = ?', whereArgs: [date]);
      await tx.delete('plans', where: 'date = ?', whereArgs: [date]);
      await _recordUndo(
        tx,
        'Quitar calendario · $date',
        'plan',
        date,
        beforeUndo,
        await _planState(tx, date),
      );
    });
  }

  Future<Map<String, List<Map<String, Object?>>>> snapshot() =>
      db.transaction((tx) async {
        final result = <String, List<Map<String, Object?>>>{};
        for (final table in tables) {
          result[table] = await tx.query(table);
        }
        return result;
      });
  Future<void> replaceData(Map<String, List<Map<String, Object?>>> rows) async {
    await db.transaction((tx) async {
      await tx.delete('undo_actions');
      for (final table in tables.reversed) {
        await tx.delete(table);
      }
      for (final table in tables) {
        for (final row in rows[table]!) {
          await tx.insert(table, row);
        }
      }
    });
    try {
      await cleanupPhotos();
    } on FileSystemException {
      /* committed data remains valid */
    }
  }

  Future<void> cleanupPhotos() async {
    final used = (await db.query(
      'garments',
      columns: ['photo', 'source_photo'],
    )).expand((m) => [m['photo'], m['source_photo']]).toSet();
    used.addAll(
      (await db.query(
        'outfits',
        columns: ['reference_photo'],
      )).map((m) => m['reference_photo']),
    );
    await for (final file in Directory(p.join(root.path, 'photos')).list()) {
      if (file is File && !used.contains(p.basename(file.path))) {
        // Cleanup must never turn a committed save into an apparent failure.
        try {
          await file.delete();
        } on FileSystemException {
          /* retry next cleanup */
        }
      }
    }
  }

  Future<Map<String, Object?>> _planState(
    DatabaseExecutor tx,
    String date,
  ) async {
    final feedback = await tx.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['usage_feedback'],
    );
    return {
      'plans': await tx.query('plans', where: 'date = ?', whereArgs: [date]),
      'wears': await tx.query(
        'garment_wears',
        where: 'date = ?',
        whereArgs: [date],
        orderBy: 'garment_id',
      ),
      'feedback': feedback.isEmpty
          ? <Object?>[]
          : readEntries(feedback.first['value'] as String)
                .where((e) => e['id'] == date)
                .toList(),
    };
  }

  Future<List<Map<String, Object?>>> _garmentState(
    DatabaseExecutor tx,
    Set<String> ids,
  ) async {
    final rows = <Map<String, Object?>>[];
    for (final id in ids.toList()..sort()) {
      rows.addAll(await tx.query('garments', where: 'id = ?', whereArgs: [id]));
    }
    return rows;
  }

  String _canonical(Object? value) {
    Object? sorted(Object? v) {
      if (v is Map) {
        final keys = v.keys.cast<String>().toList()..sort();
        return {for (final k in keys) k: sorted(v[k])};
      }
      if (v is List) return v.map(sorted).toList();
      return v;
    }

    return jsonEncode(sorted(value));
  }

  Future<void> _recordUndo(
    DatabaseExecutor tx,
    String label,
    String kind,
    Object target,
    Object before,
    Object after,
  ) async {
    if (_canonical(before) == _canonical(after)) return;
    await tx.insert('undo_actions', {
      'label': label,
      'data': jsonEncode({
        'kind': kind,
        'target': target,
        'before': before,
        'after': after,
      }),
    });
    await tx.execute(
      'DELETE FROM undo_actions WHERE id NOT IN (SELECT id FROM undo_actions ORDER BY id DESC LIMIT 10)',
    );
  }

  Future<String?> lastUndoLabel() async {
    final rows = await db.query('undo_actions', orderBy: 'id DESC', limit: 1);
    return rows.isEmpty ? null : rows.first['label'] as String;
  }

  Future<void> undoLast() async {
    await db.transaction((tx) async {
      final rows = await tx.query('undo_actions', orderBy: 'id DESC', limit: 1);
      if (rows.isEmpty) {
        throw const FormatException('No hay acciones para deshacer.');
      }
      final entry =
          jsonDecode(rows.first['data'] as String) as Map<String, dynamic>;
      if (entry['kind'] == 'plan' || entry['kind'] == 'week') {
        final dates = entry['kind'] == 'plan'
            ? [entry['target'] as String]
            : (entry['target'] as List).cast<String>();
        for (final date in dates) {
          final current = await _planState(tx, date);
          if (_canonical(current) !=
              _canonical(
                entry['kind'] == 'plan' ? entry['after'] : entry['after'][date],
              )) {
            throw const FormatException(
              'El calendario o su valoración cambió después. Se conserva la información actual.',
            );
          }
          final before =
              (entry['kind'] == 'plan'
                      ? entry['before']
                      : entry['before'][date])
                  as Map;
          for (final row in before['plans'] as List) {
            if ((await tx.query(
              'outfits',
              where: 'id = ?',
              whereArgs: [row['outfit_id']],
            )).isEmpty) {
              throw const FormatException(
                'El outfit anterior ya no existe; no se puede recuperar la asignación.',
              );
            }
          }
          for (final row in before['wears'] as List) {
            if ((await tx.query(
              'garments',
              where: 'id = ?',
              whereArgs: [row['garment_id']],
            )).isEmpty) {
              throw const FormatException(
                'Una prenda del uso original ya no existe.',
              );
            }
          }
          await tx.delete(
            'garment_wears',
            where: 'date = ?',
            whereArgs: [date],
          );
          await tx.delete('plans', where: 'date = ?', whereArgs: [date]);
          for (final row in before['plans'] as List) {
            await tx.insert('plans', Map<String, Object?>.from(row as Map));
          }
          for (final row in before['wears'] as List) {
            await tx.insert(
              'garment_wears',
              Map<String, Object?>.from(row as Map),
            );
          }
          final saved = await tx.query(
            'settings',
            where: 'key = ?',
            whereArgs: ['usage_feedback'],
          );
          final feedback = saved.isEmpty
              ? <Map<String, dynamic>>[]
              : readEntries(saved.first['value'] as String);
          feedback.removeWhere((e) => e['id'] == date);
          feedback.addAll(
            (before['feedback'] as List).map(
              (e) => Map<String, dynamic>.from(e as Map),
            ),
          );
          if (feedback.isNotEmpty || saved.isNotEmpty) {
            await tx.insert('settings', {
              'key': 'usage_feedback',
              'value': writeEntries(feedback),
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
      } else {
        final ids = (entry['target'] as List).cast<String>().toSet();
        if (_canonical(await _garmentState(tx, ids)) !=
            _canonical(entry['after'])) {
          throw const FormatException(
            'Alguna ficha cambió después. Se conservan los datos actuales.',
          );
        }
        for (final row in entry['before'] as List) {
          final map = Map<String, Object?>.from(row as Map);
          await tx.update(
            'garments',
            map,
            where: 'id = ?',
            whereArgs: [map['id']],
          );
        }
      }
      await tx.delete(
        'undo_actions',
        where: 'id = ?',
        whereArgs: [rows.first['id']],
      );
    });
  }

  Future<void> close() => db.close();
}
