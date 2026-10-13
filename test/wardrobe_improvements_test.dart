import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_armario/models.dart';
import 'package:mi_armario/repository.dart';
import 'package:mi_armario/recommendation_service.dart';
import 'package:mi_armario/wardrobe_tools.dart';
import 'package:mi_armario/backup_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory root;
  late WardrobeRepository repo;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('wardrobe_v12_');
    repo = await WardrobeRepository.open(root);
  });
  tearDown(() async {
    await repo.close();
    await root.delete(recursive: true);
  });
  Future<Garment> add(
    String id, {
    String category = 'Parte superior',
    String status = 'Disponible',
    String? source,
  }) async {
    final photo = await repo.importPhoto('test/fixtures/camiseta.png');
    final g = Garment(
      id: id,
      name: id,
      category: category,
      photo: photo,
      status: status,
      sourcePhoto: source ?? '',
      color: 'Azul',
    );
    await repo.saveGarment(g);
    return g;
  }

  test(
    'Migración SQLite 2 a 3 conserva prenda y añade disponibilidad',
    () async {
      await add('old');
      await repo.db.execute('ALTER TABLE garments DROP COLUMN details');
      await repo.db.execute('ALTER TABLE outfits DROP COLUMN reference_photo');
      await repo.db.execute('ALTER TABLE garments DROP COLUMN subtype');
      await repo.db.execute('ALTER TABLE garments DROP COLUMN status');
      await repo.db.execute('ALTER TABLE garments DROP COLUMN source_photo');
      await repo.db.setVersion(2);
      await repo.close();
      repo = await WardrobeRepository.open(root);
      expect(await repo.db.getVersion(), 5);
      final g = (await repo.garments()).single;
      expect(g.id, 'old');
      expect(g.status, 'Disponible');
      expect(g.sourcePhoto, '');
    },
  );
  test(
    'Ropa no disponible excluida y varias prendas fijadas conservadas',
    () async {
      final top = await add('top'),
          bottom = await add('bottom', category: 'Parte inferior'),
          coat = await add('coat', category: 'Abrigos');
      await add('washing', status: 'En lavado');
      await add('stored', category: 'Vestidos', status: 'Guardada');
      final all = await repo.garments();
      final s = RecommendationService.suggest(
        garments: all,
        usage: {},
        date: DateTime(2026, 10, 12),
        climate: Climate.mild,
        requiredIds: {top.id, bottom.id, coat.id},
      );
      expect(s, isNotEmpty);
      expect(
        s.first.garments.map((g) => g.id),
        containsAll(['top', 'bottom', 'coat']),
      );
      expect(s.expand((s) => s.garments).every((g) => g.available), true);
      expect(
        RecommendationService.suggest(
          garments: all,
          usage: {},
          date: DateTime.now(),
          climate: Climate.mild,
          anchorId: 'washing',
        ),
        isEmpty,
      );
    },
  );
  test(
    'Valoraciones locales evitan combinación descartada y se pueden reiniciar',
    () async {
      final a = await add('a'),
          b = await add('b'),
          bottom = await add('bottom', category: 'Parte inferior');
      final prefs = StylePreferences()
        ..rate([a, bottom], false)
        ..rate([b, bottom], true);
      final decoded = StylePreferences.decode(prefs.encode());
      final s = RecommendationService.suggest(
        garments: await repo.garments(),
        usage: {},
        date: DateTime.now(),
        climate: Climate.mild,
        preferences: decoded,
      );
      expect(
        s,
        everyElement(
          predicate<OutfitSuggestion>(
            (s) => !s.garments.any((g) => g.id == 'a'),
          ),
        ),
      );
      expect(s.first.garments.map((g) => g.id), contains('b'));
      expect(StylePreferences().outfits, isEmpty);
      expect(validToolSetting('style_preferences', prefs.encode()), true);
    },
  );
  test(
    'Copia 3 recupera original, estado, preferencias y maleta preparada',
    () async {
      final source = await repo.importPhoto('test/fixtures/pantalon.png');
      final g = await add('g', source: source, status: 'En lavado');
      final bag = {
        'id': 'trip',
        'name': 'Viaje',
        'start': '2026-10-12',
        'end': '2026-10-15',
        'items': [g.id],
        'packed': [g.id],
        'occasion': 'Diario',
        'climate': 'mild',
      };
      await repo.saveSetting(
        'suitcases',
        jsonEncode({
          'bags': [bag],
        }),
      );
      await repo.saveSetting(
        'style_preferences',
        (StylePreferences()..rate([g], true)).encode(),
      );
      await repo.saveSetting(
        'backup_reminder',
        jsonEncode({
          'enabled': true,
          'last_export': '2026-10-12',
          'snooze_until': '',
        }),
      );
      final old = await File(repo.photoPath(source)).readAsBytes();
      await BackupService(repo).restore(await BackupService(repo).export());
      final recovered = (await repo.garments()).single;
      expect(recovered.status, 'En lavado');
      expect(recovered.sourcePhoto, isNot(source));
      expect(
        await File(repo.photoPath(recovered.sourcePhoto)).readAsBytes(),
        old,
      );
      expect(
        (jsonDecode((await repo.setting('suitcases'))!)['bags'] as List)
            .single['packed'],
        ['g'],
      );
      await repo.cleanupPhotos();
      expect(await File(repo.photoPath(recovered.sourcePhoto)).exists(), true);
    },
  );
  test(
    'Formato 2 se adapta y copias con maletas inválidas se rechazan',
    () async {
      await add('g');
      final data = await repo.snapshot();
      data['garments'] = data['garments']!
          .map(
            (m) => Map<String, Object?>.from(m)
              ..remove('details')
              ..remove('subtype')
              ..remove('status')
              ..remove('source_photo'),
          )
          .toList();
      final migrated = BackupService.validateManifest({
        'format': 'mi_armario',
        'version': 2,
        'data': data,
      });
      expect(migrated['garments']!.single['status'], 'Disponible');
      migrated['settings'] = [
        {
          'key': 'suitcases',
          'value': jsonEncode({
            'bags': [
              {'id': 'broken'},
            ],
          }),
        },
      ];
      expect(
        () => BackupService.validateManifest({
          'format': 'mi_armario',
          'version': 5,
          'data': migrated,
        }),
        throwsFormatException,
      );
      expect(validToolSetting('backup_reminder', '{"enabled":"yes"}'), false);
    },
  );
  test(
    'Olvidadas excluye ropa guardada y distingue falta de historial',
    () async {
      final never = await add('never'),
          old = await add('old'),
          recent = await add('recent');
      await add('stored', status: 'Guardada');
      final result = forgottenGarments(await repo.garments(), {
        old.id: WearStat(count: 4, lastWorn: DateTime(2026, 9, 1)),
        recent.id: WearStat(count: 1, lastWorn: DateTime(2026, 10, 10)),
      }, DateTime(2026, 10, 12));
      expect(result.map((g) => g.id), [never.id, old.id]);
    },
  );
  test('Recordatorio semanal respeta desactivación y aplazamiento', () {
    final now = DateTime(2026, 10, 12);
    expect(backupDue({}, now, hasData: true), true);
    expect(backupDue({}, now, hasData: false), false);
    expect(backupDue({'enabled': false}, now, hasData: true), false);
    expect(backupDue({'last_export': '2026-10-06'}, now, hasData: true), false);
    expect(backupDue({'last_export': '2026-10-05'}, now, hasData: true), true);
    expect(
      backupDue({'snooze_until': '2026-10-13'}, now, hasData: true),
      false,
    );
  });
  test('Duplicados son candidatos y descarta imágenes planas y categorías distintas', () async {
    final a = await add('a'),
        b = await add('b'),
        different = await add('shoe', category: 'Calzado');
    final hash = List.generate(64, (i) => i.isEven ? '1' : '0').join();
    expect(
      DuplicateService.compare(
        [a, b, different],
        {'a': hash, 'b': hash, 'shoe': hash},
      ),
      hasLength(1),
    );
    expect(
      DuplicateService.compare([a, b], {'a': '0' * 64, 'b': '0' * 64}),
      isEmpty,
    );
  });
  testWidgets(
    'Pincel borra y recupera píxeles originales sin alterar el resto',
    (tester) async {
      await tester.runAsync(() async {
        final sourceRecorder = ui.PictureRecorder();
        ui.Canvas(sourceRecorder)
            .drawColor(const Color(0xffff0000), ui.BlendMode.src);
        final picture = sourceRecorder.endRecording();
        final source = await picture.toImage(16, 16);
        picture.dispose();
        final recorder = ui.PictureRecorder();
        paintCutout(ui.Canvas(recorder), source, source, [
          BrushStroke([const Offset(8, 8)], 3, false),
        ]);
        final cutPicture = recorder.endRecording();
        final cut = await cutPicture.toImage(16, 16);
        cutPicture.dispose();
        final pixels = (await cut.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        expect(pixels[(8 * 16 + 8) * 4 + 3], 0);
        expect(pixels[3], 255);
        final r = ui.PictureRecorder();
        paintCutout(ui.Canvas(r), cut, source, [
          BrushStroke([const Offset(8, 8)], 3, true),
        ]);
        final p = r.endRecording();
        final restored = await p.toImage(16, 16);
        p.dispose();
        final restoredPixels = (await restored.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        expect(restoredPixels[(8 * 16 + 8) * 4], 255);
        expect(restoredPixels[(8 * 16 + 8) * 4 + 3], 255);
        restored.dispose();
        cut.dispose();
        source.dispose();
      });
    },
  );
}
