import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_armario/models.dart';
import 'package:mi_armario/local_photo_service.dart';
import 'package:mi_armario/recommendation_service.dart';
import 'package:mi_armario/recommendations_screen.dart';
import 'package:mi_armario/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'async_ui.dart';

void main() {
  test('Diagnóstico distingue fotos sin guardar, falta de categorías y disponibilidad', () {
    Garment piece(String id, String category, {String status = 'Disponible'}) =>
        Garment(
          id: id,
          name: id,
          category: category,
          photo: 'photo.png',
          status: status,
        );
    expect(
      RecommendationService.noSuggestionReason([]),
      contains('Guardar prenda'),
    );
    expect(
      RecommendationService.noSuggestionReason([piece('g', 'Parte superior')]),
      contains('Falta una parte inferior'),
    );
    expect(
      RecommendationService.noSuggestionReason([piece('g', 'Parte inferior')]),
      contains('Falta una parte superior'),
    );
    expect(
      RecommendationService.noSuggestionReason([
        piece('g', 'Vestidos', status: 'En lavado'),
      ]),
      contains('están en lavado'),
    );
    expect(
      RecommendationService.noSuggestionReason([
        piece('g', 'Parte superior'),
        piece('dress', 'Vestidos'),
      ], anchorId: 'g'),
      contains('para combinar con «g»'),
    );
  });
  test('Análisis parcial conserva colores y expone aviso; fallos muestran tipo sin rutas', () {
    final result = PhotoAnalysis.fromMap({
      'colors': ['Azul'],
      'warning': 'Categoría no disponible',
      'category': null,
    });
    expect(result.colors, ['Azul']);
    expect(result.warning, 'Categoría no disponible');
    expect(
      photoErrorMessage(
        PlatformException(
          code: 'local_photo',
          message: 'No se ha podido iniciar el motor local de fotos.',
          details: {'type': 'NoSuchMethodError', 'operation': 'analyze'},
        ),
      ),
      contains('Código: NoSuchMethodError'),
    );
  });
  testWidgets(
    'Ideas explica categorías importadas y permite selección manual y planificación',
    (tester) async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      late Directory root;
      late WardrobeRepository repo;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('ideas_regression_');
        repo = await WardrobeRepository.open(root);
        await repo.saveGarment(
          Garment(
            id: 'g',
            name: 'Camiseta importada',
            category: 'Parte superior',
            photo: await repo.importPhoto('test/fixtures/camiseta.png'),
          ),
        );
      });
      addTearDown(() async {
        await repo.close();
        await root.delete(recursive: true);
      });
      tester.view.physicalSize = const Size(412, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(home: RecommendationsScreen(repo: repo)),
      );
      await waitForWidget(
        tester,
        find.text('Elegir prendas y planificar manualmente'),
      );
      expect(find.text('Personaliza tu idea'), findsOneWidget);
      await tester.tap(find.text('Personaliza tu idea'));
      await tester.pumpAndSettle();
      expect(find.text('Estilo preferido'), findsOneWidget);
      await tester.tap(find.text('Personaliza tu idea'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining('Falta una parte inferior'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Falta una parte inferior'), findsOneWidget);
      // El botón está por encima del diagnóstico; vuelve a él con el scroll
      // antes de interactuar, en lugar de pedir ensureVisible a un hijo no montado.
      await tester.scrollUntilVisible(
        find.text('Elegir prendas y planificar manualmente'),
        -150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elegir prendas y planificar manualmente'));
      await waitForWidget(tester, find.text('Añadir prenda'));
      await waitForWidget(tester, find.text('Añadir prenda'));
      await tester.tap(find.text('Añadir prenda'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Camiseta importada'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Guardar outfit'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar outfit'));
      await waitForWidget(
        tester,
        find.textContaining('Outfit guardado y asignado'),
      );
      await tester.runAsync(() async {
        final plans = await repo.plans();
        expect(plans, hasLength(1));
        expect(plans.single.date, dateKey(DateTime.now()));
        expect((await repo.outfits()).single.items.single.garmentId, 'g');
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
