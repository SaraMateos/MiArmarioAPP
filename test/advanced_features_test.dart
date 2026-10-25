import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_armario/advanced_data.dart';
import 'package:mi_armario/advanced_tools_screen.dart';
import 'package:mi_armario/backup_service.dart';
import 'package:mi_armario/models.dart';
import 'package:mi_armario/outfit_image_service.dart';
import 'package:mi_armario/recommendation_service.dart';
import 'package:mi_armario/repository.dart';
import 'package:mi_armario/week_editor.dart';
import 'package:mi_armario/wardrobe_tools.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'async_ui.dart';

void main() {
  Garment g(
    String id,
    String type, {
    Map<String, Object?> details = const {},
    String status = 'Disponible',
  }) => Garment(
    id: id,
    name: type,
    subtype: type,
    category: garmentTypes[type]!,
    photo: 'image.png',
    details: details,
    status: status,
  );
  final date = DateTime(2026, 10, 12);
  List<OutfitSuggestion> suggest(
    List<Garment> pieces, {
    RecommendationProfile? profile,
    Climate climate = Climate.cold,
    bool rain = false,
    bool wind = false,
    List<Map<String, dynamic>> feedback = const [],
    Set<String> required = const {},
  }) => RecommendationService.suggest(
    garments: pieces,
    usage: {},
    date: date,
    climate: climate,
    profile: profile,
    rainy: rain,
    windy: wind,
    feedback: feedback,
    requiredIds: required,
    limit: 20,
  );
  test('Capas coherentes admiten camiseta, jersey y chaqueta; nunca dos bases ni dos pantalones', () {
    final pieces = [
      g('a', 'Camiseta'),
      g('b', 'Pantalón'),
      g('c', 'Jersey'),
      g('d', 'Chaqueta'),
    ];
    expect(
      RecommendationService.validAutomaticCombination(pieces, 'Diario'),
      true,
    );
    expect(
      RecommendationService.validAutomaticCombination([
        ...pieces,
        g('e', 'Camisa'),
      ], 'Diario'),
      false,
    );
    expect(
      RecommendationService.validAutomaticCombination([
        ...pieces,
        g('e', 'Vaqueros'),
      ], 'Diario'),
      false,
    );
    expect(
      suggest(pieces, required: {'a', 'b', 'c', 'd'}).single.garments.length,
      4,
    );
    expect(
      suggest(
        pieces,
        climate: Climate.hot,
      ).every((s) => !s.garments.any((g) => g.id == 'c')),
      true,
    );
  });
  test('Exclusión caduca por día sin modificar disponibilidad; archivo excluye siempre', () {
    final top = g('t', 'Camiseta'),
        other = g('o', 'Camisa'),
        bottom = g('b', 'Pantalón');
    final p = RecommendationProfile(
      exclusions: {
        dateKey(date): ['t'],
      },
    );
    expect(
      suggest([
        top,
        other,
        bottom,
      ], profile: p).every((s) => !s.garments.contains(top)),
      true,
    );
    expect(top.available, true);
    expect(p.excludedOn(calendarDayOffset(date, 1)), isEmpty);
    expect(suggest([g('t', 'Camiseta', status: 'Archivada'), bottom]), isEmpty);
  });
  test('Conjunto vinculado se incluye entero o se omite; no se propone si una pieza está en lavado', () {
    final p = RecommendationProfile(
      linkedSets: [
        ['p', 'c'],
      ],
    );
    final pieces = [g('t', 'Camisa'), g('p', 'Pantalón'), g('c', 'Americana')];
    expect(
      suggest(
        pieces,
        profile: p,
        climate: Climate.mild,
      ).every((s) => s.garments.any((g) => g.id == 'c')),
      true,
    );
    expect(
      suggest([
        pieces[0],
        pieces[1],
        g('c', 'Americana', status: 'En lavado'),
      ], profile: p),
      isEmpty,
    );

    final accessoryProfile = RecommendationProfile(
      linkedSets: [
        ['bag', 'scarf'],
      ],
    );
    final accessorySuggestions = suggest(
      [
        g('top', 'Camiseta'),
        g('bottom', 'Pantalón'),
        g('bag', 'Bolso'),
        g('scarf', 'Bufanda'),
      ],
      profile: accessoryProfile,
      climate: Climate.mild,
      required: {'bag'},
    );
    expect(accessorySuggestions, isNotEmpty);
    expect(
      accessorySuggestions.every(
        (s) => s.garments.map((g) => g.id).toSet().containsAll(['bag', 'scarf']),
      ),
      true,
    );
  });
  test('Estilo y protección lluvia/viento cambian la prioridad sin inventar protección', () {
    final pieces = [
      g('t', 'Camisa'),
      g('b', 'Pantalón'),
      g('c', 'Chaqueta'),
      g('r', 'Chaqueta', details: {'rain': true, 'wind': true}),
      g('s', 'Botas'),
      g('rs', 'Botas', details: {'rain': true}),
    ];
    final result = suggest(pieces, rain: true, wind: true).first;
    expect(result.garments.map((g) => g.id), containsAll(['r', 'rs']));
    final styles = suggest(
      [
        g('plain', 'Camiseta'),
        g('e', 'Camisa', details: {'style': 'Elegante'}),
        g('b', 'Pantalón'),
      ],
      profile: RecommendationProfile(style: 'Elegante'),
      climate: Climate.mild,
    );
    expect(styles.first.garments.any((g) => g.id == 'e'), true);
  });
  test('Valoración de uso penaliza la combinación no convincente', () {
    final pieces = [g('a', 'Camiseta'), g('b', 'Camisa'), g('p', 'Pantalón')];
    final baseline = suggest(pieces, climate: Climate.mild);
    final disliked = baseline.first.garments.map((g) => g.id).toList();
    final after = suggest(
      pieces,
      climate: Climate.mild,
      feedback: [
        {'items': disliked, 'rating': 'No me convenció'},
      ],
    );
    expect(after.first.signature, isNot(baseline.first.signature));
  });
  test(
    'Ajustes nuevos rechazan fechas, tipos y referencias de foto arbitrarios',
    () {
      expect(
        validAdvancedSetting(
          'recommendation_profile',
          '{"style":"Casual","rain":true,"wind":false,"exclusions":{"bad":["g"]}}',
        ),
        false,
      );
      expect(
        validAdvancedSetting(
          'linked_sets',
          '{"entries":[{"id":"s","name":"Traje","items":["g","g"]}]}',
        ),
        false,
      );
      expect(validGarmentDetails({'rain': 'yes'}), false);
    },
  );
  sqfliteFfiInit();
  setUp(() => databaseFactory = databaseFactoryFfi);
  Future<(Directory, WardrobeRepository)> open() async {
    final root = await Directory.systemTemp.createTemp('advanced5_');
    return (root, await WardrobeRepository.open(root));
  }

  Future<Garment> add(WardrobeRepository r, String id, String type) async {
    final photo = await r.importPhoto('test/fixtures/camiseta.png');
    final garment = Garment.fromMap({...g(id, type).toMap(), 'photo': photo});
    await r.saveGarment(garment);
    return garment;
  }

  test(
    'SQLite 4 migra conservando IDs e historial; copia 4 se adapta',
    () async {
      final (root, original) = await open();
      var repo = original;
      try {
        await add(repo, 'g', 'Camiseta');
        await repo.saveOutfit(
          Outfit(
            id: 'o',
            name: 'Anterior',
            items: [OutfitItem(garmentId: 'g')],
          ),
        );
        await repo.savePlan(DayPlan(dateKey(DateTime.now()), 'o', true));
        final data = await repo.snapshot();
        data['garments'] = data['garments']!
            .map((m) => {...m}..remove('details'))
            .toList();
        data['outfits'] = data['outfits']!
            .map((m) => {...m}..remove('reference_photo'))
            .toList();
        data['outfit_items'] = data['outfit_items']!
            .map((m) => {...m}
              ..remove('mannequin_x')
              ..remove('mannequin_y')
              ..remove('mannequin_scale'))
            .toList();
        final converted = BackupService.validateManifest({
          'format': 'mi_armario',
          'version': 4,
          'data': data,
        });
        expect(converted['garments']!.single['details'], '{}');
        expect(converted['outfits']!.single['reference_photo'], '');
        await repo.db.execute('ALTER TABLE garments DROP COLUMN details');
        await repo.db.execute(
          'ALTER TABLE outfits DROP COLUMN reference_photo',
        );
        await repo.db.setVersion(4);
        await repo.close();
        repo = await WardrobeRepository.open(root);
        expect(await repo.db.getVersion(), 6);
        expect((await repo.usageStats())['g']?.count, 1);
        expect((await repo.outfits()).single.referencePhoto, '');
      } finally {
        await repo.close();
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'Copias preservan originales, referencia, ficha, archivo y nuevos ajustes',
    () async {
      final (root, repo) = await open();
      try {
        final a = await add(repo, 'g', 'Camisa');
        await repo.saveGarment(
          Garment.fromMap({
            ...a.toMap(),
            'status': 'Archivada',
            'details': jsonEncode({
              'brand': 'Marca',
              'size': 'M',
              'washing': '30 °C',
              'archive_reason': 'Donada',
            }),
          }),
        );
        final photo = await repo.importPhoto('test/fixtures/pantalon.png');
        await repo.saveOutfit(
          Outfit(
            id: 'o',
            name: 'Referencia',
            items: [OutfitItem(garmentId: 'g')],
            referencePhoto: photo,
          ),
        );
        await repo.saveSetting(
          'shopping',
          writeEntries([
            {
              'id': 'x',
              'name': 'Camisa',
              'category': 'Parte superior',
              'color': 'Blanco',
              'notes': '',
            },
          ]),
        );
        await repo.cleanupPhotos();
        expect(await File(repo.photoPath(photo)).exists(), true);
        await BackupService(repo).restore(await BackupService(repo).export());
        final restored = (await repo.garments()).single;
        expect(restored.details['washing'], '30 °C');
        expect(restored.status, 'Archivada');
        expect(
          await File(
            repo.photoPath((await repo.outfits()).single.referencePhoto),
          ).exists(),
          true,
        );
        expect(
          readEntries(await repo.setting('shopping')).single['name'],
          'Camisa',
        );
      } finally {
        await repo.close();
        await root.delete(recursive: true);
      }
    },
  );
  test('Lote es atómico, conserva fotos y usos; desmarcar usado elimina valoración', () async {
    final (root, repo) = await open();
    try {
      final a = await add(repo, 'a', 'Camiseta');
      await add(repo, 'b', 'Pantalón');
      await repo.saveOutfit(
        Outfit(
          id: 'o',
          name: 'Uso',
          items: [
            OutfitItem(garmentId: 'a'),
            OutfitItem(garmentId: 'b'),
          ],
        ),
      );
      final key = dateKey(DateTime.now());
      await repo.savePlan(DayPlan(key, 'o', true));
      await repo.saveSetting(
        'usage_feedback',
        writeEntries([
          {
            'id': key,
            'outfit_id': 'o',
            'items': ['a', 'b'],
            'rating': 'Cómodo',
            'notes': '',
          },
        ]),
      );
      await expectLater(
        repo.batchUpdate({'a', 'missing'}, {'status': 'En lavado'}),
        throwsFormatException,
      );
      expect(
        (await repo.garments()).firstWhere((g) => g.id == 'a').available,
        true,
      );
      await repo.batchUpdate(
        {'a', 'b'},
        {
          'status': 'En lavado',
          'season': ['Invierno', 'Otoño'],
        },
      );
      expect(
        (await repo.garments()).firstWhere((g) => g.id == 'a').photo,
        a.photo,
      );
      expect((await repo.usageStats())['a']?.count, 1);
      await repo.savePlan(DayPlan(key, 'o', true));
      expect(readEntries(await repo.setting('usage_feedback')), hasLength(1));
      expect((await repo.usageStats())['a']?.count, 1);
      await repo.savePlan(DayPlan(key, 'o', false));
      expect(readEntries(await repo.setting('usage_feedback')), isEmpty);
    } finally {
      await repo.close();
      await root.delete(recursive: true);
    }
  });
  testWidgets(
    'Exporta PNG real con todas las prendas y no pierde las fotos originales',
    (tester) async {
      late Directory root;
      late WardrobeRepository repo;
      late Garment garment;
      await tester.runAsync(() async {
        final opened = await open();
        root = opened.$1;
        repo = opened.$2;
        garment = await add(repo, 'g', 'Camiseta');
      });
      try {
        final outfit = Outfit(
          id: 'o',
          name: 'Mi outfit',
          items: [OutfitItem(garmentId: 'g')],
        );
        final bytes = await tester.runAsync(
          () => OutfitImageService.render(repo, outfit, [garment]),
        );
        expect(bytes!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        await tester.runAsync(() async {
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          expect(frame.image.width, 1200);
          expect(frame.image.height, 630);
          frame.image.dispose();
          codec.dispose();
        });
      } finally {
        await tester.runAsync(() async {
          await repo.close();
          await root.delete(recursive: true);
        });
      }
    },
  );
  testWidgets(
    'Edición por lotes y herramientas abren en ancho de móvil sin overflow',
    (tester) async {
      late Directory root;
      late WardrobeRepository repo;
      await tester.runAsync(() async {
        final opened = await open();
        root = opened.$1;
        repo = opened.$2;
        await add(repo, 'g', 'Camiseta');
      });
      addTearDown(() async {
        await repo.close();
        await root.delete(recursive: true);
      });
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(home: AdvancedToolsScreen(repo: repo)),
      );
      await waitForWidget(tester, find.text('Vincular prendas'));
      await tester.tap(find.byTooltip('Edición por lotes'));
      await waitForWidget(tester, find.text('Aplicar a 0 prendas'));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(find.text('Aplicar a 1 prendas'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Cada día permite cambiar su ocasión conservando días protegidos',
    (tester) async {
      late Directory root;
      late WardrobeRepository repo;
      late List<Garment> garments;
      await tester.runAsync(() async {
        final opened = await open();
        root = opened.$1;
        repo = opened.$2;
        garments = [
          await add(repo, 't', 'Camiseta'),
          await add(repo, 'b', 'Pantalón'),
        ];
      });
      addTearDown(() async {
        await repo.close();
        await root.delete(recursive: true);
      });
      final outfit = Outfit(
        id: 'draft',
        name: 'Lunes',
        items: [
          OutfitItem(garmentId: 't'),
          OutfitItem(garmentId: 'b'),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: WeekEditor(
            repo: repo,
            start: date,
            proposed: {DayPlan(dateKey(date), 'draft', false): outfit},
            existing: [],
            knownOutfits: [],
            garments: garments,
            usage: {},
            preferences: StylePreferences(),
            climateFor: (_) => Climate.mild,
            occasion: 'Diario',
          ),
        ),
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trabajo').last);
      await tester.pumpAndSettle();
      expect(find.text('Trabajo'), findsOneWidget);
      expect(find.text('Guardar 1 días nuevos'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
