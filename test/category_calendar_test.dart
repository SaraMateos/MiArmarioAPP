import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_armario/models.dart';
import 'package:mi_armario/recommendation_service.dart';
import 'package:mi_armario/repository.dart';
import 'package:mi_armario/backup_service.dart';
import 'package:mi_armario/planned_calendar.dart';
import 'package:mi_armario/garment_editor.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  Garment g(String id, String category, {String subtype = '', String? name}) =>
      Garment(
        id: id,
        name: name ?? id,
        category: category,
        photo: 'test.png',
        subtype: subtype,
      );
  test(
    'Dos pantalones mal clasificados no forman una base superior/inferior',
    () {
      final pieces = [
        g('a', 'Parte superior', name: 'Pantalón azul'),
        g('b', 'Parte inferior', name: 'Vaqueros negros'),
      ];
      expect(
        RecommendationService.suggest(
          garments: pieces,
          usage: {},
          date: DateTime.now(),
          climate: Climate.mild,
        ),
        isEmpty,
      );
      expect(
        RecommendationService.validAutomaticCombination(pieces, 'Diario'),
        false,
      );
      final top = g('t', 'Parte inferior', subtype: 'Camisa');
      final suggestions = RecommendationService.suggest(
        garments: [...pieces, top],
        usage: {},
        date: DateTime.now(),
        climate: Climate.mild,
      );
      expect(suggestions, isNotEmpty);
      expect(
        suggestions.every(
          (s) =>
              s.garments.where((g) => roleOf(g) == 'Parte inferior').length ==
              1,
        ),
        true,
      );
    },
  );
  test('Tipos deportivos y formales incompatibles se excluyen', () {
    expect(
      RecommendationService.validAutomaticCombination([
        g('s', 'Parte superior', subtype: 'Camiseta deportiva'),
        g('f', 'Calzado', subtype: 'Zapatos de vestir'),
      ], 'Diario'),
      false,
    );
    expect(
      RecommendationService.validAutomaticCombination([
        g('d', 'Vestidos', subtype: 'Vestido'),
        g('p', 'Parte inferior', subtype: 'Pantalón'),
      ], 'Diario'),
      false,
    );
  });
  test('SQLite 3 a 4 y copia preservan prendas y tipo detallado', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final root = await Directory.systemTemp.createTemp('types4_');
    var repo = await WardrobeRepository.open(root);
    try {
      final photo = await repo.importPhoto('test/fixtures/pantalon.png');
      await repo.saveGarment(
        Garment(
          id: 'g',
          name: 'Pantalón',
          category: 'Parte superior',
          subtype: 'Vaqueros',
          photo: photo,
        ),
      );
      expect((await repo.garments()).single.category, 'Parte inferior');
      await BackupService(repo).restore(await BackupService(repo).export());
      expect((await repo.garments()).single.subtype, 'Vaqueros');
      await repo.db.execute('ALTER TABLE garments DROP COLUMN details');
      await repo.db.execute('ALTER TABLE outfits DROP COLUMN reference_photo');
      await repo.db.execute('ALTER TABLE garments DROP COLUMN subtype');
      for (final column in ['mannequin_x', 'mannequin_y', 'mannequin_scale']) {
        await repo.db.execute('ALTER TABLE outfit_items DROP COLUMN $column');
      }
      await repo.db.setVersion(3);
      await repo.close();
      repo = await WardrobeRepository.open(root);
      expect(await repo.db.getVersion(), 7);
      expect((await repo.garments()).single.id, 'g');
      expect((await repo.garments()).single.subtype, '');
    } finally {
      await repo.close();
      await root.delete(recursive: true);
    }
  });
  testWidgets(
    'Calendario marca planificado/usado y mantiene selección al cambiar mes',
    (tester) async {
      DateTime selected = DateTime(2026, 10, 12);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlannedCalendar(
              selected: selected,
              plans: [
                const DayPlan('2026-10-13', 'a', false),
                const DayPlan('2026-10-14', 'b', true),
              ],
              onChanged: (d) => selected = d,
            ),
          ),
        ),
      );
      expect(find.byTooltip('Outfit planificado'), findsOneWidget);
      expect(find.byTooltip('Outfit usado'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('calendar-2026-10-13')));
      expect(dateKey(selected), '2026-10-13');
      await tester.tap(find.byTooltip('Mes siguiente'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('calendar-2026-11-01')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Foto importada recibe ejemplo de nombre y respeta edición manual',
    (tester) async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      late Directory root;
      late WardrobeRepository repo;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('autoname_');
        repo = await WardrobeRepository.open(root);
      });
      addTearDown(() async {
        await repo.close();
        await root.delete(recursive: true);
      });
      const channel = MethodChannel('es.personal.mi_armario/local_photo');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => {
              'category': 'Parte inferior',
              'name': 'Pantalón',
              'colors': ['Azul'],
              'confidence': .9,
            },
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: GarmentEditor(
            repo: repo,
            recoveredPhoto: 'test/fixtures/pantalon.png',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final name = find.byType(TextFormField).first;
      await tester.scrollUntilVisible(
        find.text('Nombre de la prenda'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester.widget<TextFormField>(name).controller!.text,
        'Pantalón azul',
      );
      final controller = tester.widget<TextFormField>(name).controller!;
      await tester.enterText(name, 'Mis vaqueros');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final tools = find.text('Herramientas de fotografía');
      await tester.scrollUntilVisible(
        tools,
        -150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(tools);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Detectar datos'),
        -150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Detectar datos'));
      await tester.pumpAndSettle();
      expect(controller.text, 'Mis vaqueros');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
