import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mi_armario/batch_import_screen.dart';
import 'package:mi_armario/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'async_ui.dart';

void main() {
  testWidgets(
    'Importación de dos fotos con colores, temporadas y ocasiones múltiples',
    (tester) async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      late Directory root;
      late WardrobeRepository repo;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('wardrobe_batch_');
        repo = await WardrobeRepository.open(root);
      });
      addTearDown(() async {
        await repo.close();
        await root.delete(recursive: true);
      });
      tester.view.physicalSize = const Size(412, 892);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const channel = MethodChannel('es.personal.mi_armario/local_photo');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'analyze') {
              return {
                'category': 'Parte inferior',
                'name': 'Pantalón',
                'colors': ['Azul', 'Blanco'],
                'confidence': .8,
              };
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('es'),
          supportedLocales: const [Locale('es')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: BatchImportScreen(
            repo: repo,
            files: [
              XFile('test/fixtures/camiseta.png'),
              XFile('test/fixtures/pantalon.png'),
            ],
          ),
        ),
      );
      await tester.tap(find.text('Prenda 1'));
      await tester.pumpAndSettle();
      Future<void> seeAndTap(String text) async {
        await tester.scrollUntilVisible(
          find.text(text),
          200,
          scrollable: find
              .descendant(
                of: find.byType(ListView).last,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(text));
        if (text == 'Guardar prenda') {
          return;
        }
        await tester.pumpAndSettle();
      }

      await seeAndTap('Colores, temporadas y más datos');
      await seeAndTap('Rojo');
      await seeAndTap('Primavera');
      await seeAndTap('Otoño');
      await seeAndTap('Trabajo');
      await seeAndTap('Guardar prenda');
      await waitForWidget(tester, find.text('1 guardadas de 2'));
      await tester.runAsync(() async {
        final g = (await repo.garments()).single;
        expect(g.colorTags.toSet(), {'Azul', 'Blanco', 'Rojo'});
        expect(g.seasonTags.toSet(), {'Primavera', 'Otoño'});
        expect(g.occasionTags.toSet(), {'Diario', 'Trabajo'});
      });
      await tester.tap(find.text('Prenda 2'));
      await tester.pumpAndSettle();
      await seeAndTap('Guardar prenda');
      await waitForWidget(tester, find.text('2 guardadas de 2'));
      await tester.runAsync(() async {
        final garments = await repo.garments();
        expect(garments, hasLength(2));
        expect(garments.map((g) => g.photo).toSet(), hasLength(2));
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
