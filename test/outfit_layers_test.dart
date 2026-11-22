import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_armario/models.dart';
import 'package:mi_armario/outfit_editor.dart';
import 'package:mi_armario/repository.dart';
import 'package:mi_armario/ui_common.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'async_ui.dart';

void main() {
  testWidgets(
    'Al fondo, cambiar de vista y eliminar afectan a la misma prenda',
    (tester) async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      late Directory root;
      late WardrobeRepository repo;
      late List<Garment> garments;
      final outfit = Outfit(
        id: 'outfit',
        name: 'Diario',
        items: [
          OutfitItem(garmentId: 'shirt', x: .4, y: .3),
          OutfitItem(
            garmentId: 'pants',
            x: .7,
            y: .7,
            mannequinX: .6,
            mannequinY: .8,
            mannequinScale: 1.1,
          ),
        ],
      );
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('wardrobe_layers_');
        repo = await WardrobeRepository.open(root);
        garments = [
          Garment(
            id: 'shirt',
            name: 'Mi camiseta',
            category: 'Parte superior',
            subtype: 'Camiseta',
            photo: await repo.importPhoto('test/fixtures/camiseta.png'),
          ),
          Garment(
            id: 'pants',
            name: 'Mi pantalón',
            category: 'Parte inferior',
            subtype: 'Pantalón',
            photo: await repo.importPhoto('test/fixtures/pantalon.png'),
          ),
        ];
        for (final garment in garments) {
          await repo.saveGarment(garment);
        }
        await repo.saveOutfit(outfit);
      });
      addTearDown(() async {
        await repo.close();
        await root.delete(recursive: true);
      });
      tester.view.physicalSize = const Size(500, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OutfitEditor(
                      repo: repo,
                      garments: garments,
                      outfit: outfit,
                    ),
                  ),
                ),
                child: const Text('Abrir editor'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir editor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mi pantalón'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Al fondo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maniquí'));
      await tester.pumpAndSettle();

      final board = tester.widget<OutfitBoard>(find.byType(OutfitBoard));
      expect(board.items.map((item) => item.garmentId), ['pants', 'shirt']);
      expect(
        (board.items[0].x, board.items[0].y, board.items[0].scale),
        (.6, .8, 1.1),
      );
      expect((board.items[1].x, board.items[1].y), (.5, .27));

      await tester.tap(find.text('Mi camiseta'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Eliminar prenda'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Libre'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Guardar outfit'));
      await tester.tap(find.text('Guardar outfit'));
      await waitForWidget(tester, find.text('Abrir editor'));
      await tester.runAsync(() async {
        final item = (await repo.outfits()).single.items.single;
        expect(item.garmentId, 'pants');
        expect((item.x, item.y, item.scale), (.7, .7, 1));
        expect(
          (item.mannequinX, item.mannequinY, item.mannequinScale),
          (.6, .8, 1.1),
        );
      });
    },
  );
}
