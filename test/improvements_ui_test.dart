import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_armario/models.dart';
import 'package:mi_armario/repository.dart';
import 'package:mi_armario/recommendation_service.dart';
import 'package:mi_armario/wardrobe_tools.dart';
import 'package:mi_armario/outfit_draft_screen.dart';
import 'package:mi_armario/week_editor.dart';
import 'package:mi_armario/wardrobe_tools_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory root;
  late WardrobeRepository repo;
  late List<Garment> garments;
  Future<void> prepare(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final fontDir = Platform.environment['ARMARIO_QA_FONTS'];
      if (fontDir != null) {
        for (final font in [
          ('Roboto', 'Roboto-Regular.ttf'),
          ('MaterialIcons', 'MaterialIcons-Regular.otf'),
        ]) {
          final loader = FontLoader(font.$1);
          loader.addFont(
            File('$fontDir/${font.$2}')
                .readAsBytes()
                .then((b) => ByteData.sublistView(b)),
          );
          await loader.load();
        }
      }
      root = await Directory.systemTemp.createTemp('wardrobe_v12_ui_');
      repo = await WardrobeRepository.open(root);
      garments = [];
      for (final entry in [
        ('Camiseta', 'Parte superior', 'camiseta.png'),
        ('Pantalón', 'Parte inferior', 'pantalon.png'),
        ('Otro pantalón', 'Parte inferior', 'pantalon.png'),
      ]) {
        final g = Garment(
          id: entry.$1,
          name: entry.$1,
          category: entry.$2,
          photo: await repo.importPhoto('test/fixtures/${entry.$3}'),
        );
        await repo.saveGarment(g);
        garments.add(g);
      }
    });
    addTearDown(() async {
      await repo.close();
      await root.delete(recursive: true);
    });
  }

  final boundary = GlobalKey();
  Future<void> launch(
    WidgetTester tester,
    Widget page,
    void Function(dynamic) capture,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        supportedLocales: const [Locale('es')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff355c4e),
            surface: const Color(0xfffaf8f4),
          ),
          scaffoldBackgroundColor: const Color(0xfffaf8f4),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                capture(
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          RepaintBoundary(key: boundary, child: page),
                    ),
                  ),
                );
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> screenshot(WidgetTester tester, String filename) async {
    final folder = Platform.environment['ARMARIO_QA_DIR'];
    if (folder == null) return;
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
    }
    await tester.runAsync(() async {
      final b =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await b.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(folder).create(recursive: true);
      await File('$folder/$filename.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('Fijar camiseta y sustituir pantalón conserva el resto', (
    tester,
  ) async {
    await prepare(tester);
    OutfitSuggestion? result;
    await launch(
      tester,
      OutfitDraftScreen(
        repo: repo,
        garments: garments,
        usage: {},
        preferences: StylePreferences(),
        suggestion: OutfitSuggestion(garments.take(2).toList(), 0, []),
        date: DateTime(2026, 10, 12),
        climate: Climate.mild,
        occasion: 'Diario',
      ),
      (v) => result = v as OutfitSuggestion?,
    );
    await tester.tap(find.byTooltip('Fijar prenda').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Cambiar prenda').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Otro pantalón'));
    await tester.pumpAndSettle();
    await screenshot(tester, 'ajustar_outfit');
    await tester.tap(find.text('Usar esta combinación'));
    await tester.pumpAndSettle();
    expect(result!.garments.map((g) => g.id), ['Camiseta', 'Otro pantalón']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Intercambiar semana conserva los días protegidos y devuelve borrador',
    (tester) async {
      await prepare(tester);
      final first = Outfit(
        id: 'first',
        name: 'Primero',
        items: [OutfitItem(garmentId: 'Camiseta')],
      );
      final second = Outfit(
        id: 'second',
        name: 'Segundo',
        items: [OutfitItem(garmentId: 'Pantalón')],
      );
      final existing = Outfit(
        id: 'existing',
        name: 'Existente',
        items: [OutfitItem(garmentId: 'Otro pantalón')],
      );
      Map<DayPlan, Outfit>? result;
      await launch(
        tester,
        WeekEditor(
          repo: repo,
          start: DateTime(2026, 10, 12),
          proposed: {
            const DayPlan('2026-10-12', 'first', false): first,
            const DayPlan('2026-10-13', 'second', false): second,
          },
          existing: [const DayPlan('2026-10-14', 'existing', false)],
          knownOutfits: [existing],
          garments: garments,
          usage: {},
          preferences: StylePreferences(),
          climateFor: (_) => Climate.mild,
          occasion: 'Diario',
        ),
        (v) => result = v as Map<DayPlan, Outfit>?,
      );
      await tester.tap(find.text('Mover a otro día').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SimpleDialogOption).first);
      await tester.pumpAndSettle();
      await screenshot(tester, 'semana');
      await tester.tap(find.text('Guardar 2 días nuevos'));
      await tester.pumpAndSettle();
      expect(
        result!.entries.firstWhere((e) => e.key.date == '2026-10-13').value.id,
        'first',
      );
      expect(
        result!.entries.firstWhere((e) => e.key.date == '2026-10-12').value.id,
        'second',
      );
      expect(result!.keys.any((p) => p.date == '2026-10-14'), false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Maleta conserva selección y marca preparada al guardar', (
    tester,
  ) async {
    await prepare(tester);
    Map<String, dynamic>? result;
    await launch(
      tester,
      SuitcaseEditor(repo: repo, garments: garments, usage: {}),
      (v) => result = v as Map<String, dynamic>?,
    );
    await tester.enterText(find.byType(TextField).first, 'Escapada');
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Marcar como preparada'));
    await tester.pumpAndSettle();
    await screenshot(tester, 'maleta');
    await tester.tap(find.text('Guardar maleta'));
    await tester.pumpAndSettle();
    expect(result!['items'], ['Camiseta']);
    expect(result!['packed'], ['Camiseta']);
    expect(validToolSetting('suitcases', '{"bags":[]}'), true);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
