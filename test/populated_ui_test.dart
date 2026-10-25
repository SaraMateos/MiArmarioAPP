import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_armario/home.dart';
import 'package:mi_armario/auto_framed_photo.dart';
import 'package:mi_armario/models.dart';
import 'package:mi_armario/repository.dart';
import 'package:mi_armario/ui_common.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'async_ui.dart';

void main() {
  testWidgets('Armario con fotos, filtros, outfit y persistencia de cambios', (
    tester,
  ) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    late Directory root;
    late WardrobeRepository repo;
    await tester.runAsync(() async {
      const fontDirectory = String.fromEnvironment('PREVIEW_FONT_DIRECTORY');
      if (fontDirectory.isNotEmpty) {
        for (final pair in [
          ('Roboto', 'Roboto-Regular.ttf'),
          ('MaterialIcons', 'MaterialIcons-Regular.otf'),
        ]) {
          final loader = FontLoader(pair.$1);
          loader.addFont(
            File('$fontDirectory/${pair.$2}')
                .readAsBytes()
                .then((b) => ByteData.sublistView(b)),
          );
          await loader.load();
        }
      }
      root = await Directory.systemTemp.createTemp('wardrobe_populated_');
      repo = await WardrobeRepository.open(root);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        await repo.close();
        if (await root.exists()) await root.delete(recursive: true);
      });
      for (final entry in [
        ('g1', 'Camiseta blanca', 'camiseta', 'Parte superior', 'Blanco'),
        ('g2', 'Vaqueros azules', 'pantalon', 'Parte inferior', 'Azul'),
        ('g3', 'Zapatillas', 'zapatilla', 'Calzado', 'Blanco'),
      ]) {
        final photo = await repo.importPhoto('test/fixtures/${entry.$3}.png');
        await repo.saveGarment(
          Garment(
            id: entry.$1,
            name: entry.$2,
            category: entry.$4,
            color: entry.$5,
            season: 'Todo el año',
            occasion: 'Diario',
            photo: photo,
          ),
        );
      }
      await repo.saveOutfit(
        Outfit(
          id: 'o1',
          name: 'Un día tranquilo',
          occasion: 'Diario',
          items: [
            OutfitItem(garmentId: 'g1', x: .08, y: .08, scale: 1.25),
            OutfitItem(garmentId: 'g2', x: .9, y: .4, scale: 1.45),
            OutfitItem(garmentId: 'g3', x: .06, y: .9, scale: .85),
          ],
        ),
      );
    });
    addTearDown(() async {
      await repo.close();
      await root.delete(recursive: true);
    });
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
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
          home: WardrobeHome(repo: repo),
        ),
      ),
    );
    await waitForWidget(tester, find.text('Buscar una prenda'));
    await tester.tap(find.text('Armario'));
    await waitForWidget(tester, find.bySemanticsLabel('Camiseta blanca'));
    Future<void> capture(String name) async {
      for (var frame = 0; frame < 5; frame++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();
      }
      await tester.pumpAndSettle();
      const destination = String.fromEnvironment('PREVIEW_DIRECTORY');
      if (destination.isEmpty) {
        return;
      }
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(destination).create(recursive: true);
        await File('$destination/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    expect(find.bySemanticsLabel('Camiseta blanca'), findsOneWidget);
    await capture('armario');
    await tester.tap(find.text('Parte superior'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Camiseta blanca'), findsOneWidget);
    expect(find.bySemanticsLabel('Vaqueros azules'), findsNothing);
    await tester.tap(find.text('Todas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Outfits'));
    await tester.pumpAndSettle();
    expect(find.text('Un día tranquilo'), findsOneWidget);
    await capture('outfits');
    await tester.tap(find.text('Un día tranquilo'));
    await tester.pumpAndSettle();
    await capture('editor');
    await tester.tap(find.byType(AutoFramedPhoto).first);
    await tester.drag(find.byType(Photo).first, const Offset(80, 45));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsOneWidget);
    final text = find.byType(TextFormField).first;
    await tester.scrollUntilVisible(
      find.text('Nombre del outfit'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(text, 'Outfit editado');
    await tester.scrollUntilVisible(
      find.text('Guardar outfit'),
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar outfit'));
    await waitForWidget(tester, find.text('Outfit editado'));
    await capture('guardado');
    expect(find.text('Outfit editado'), findsOneWidget);
    await tester.runAsync(() async {
      final saved = (await repo.outfits()).single;
      expect(saved.name, 'Outfit editado');
      expect(saved.items.first.x, greaterThan(.08));
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
