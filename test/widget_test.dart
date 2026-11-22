import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_armario/home.dart';
import 'package:mi_armario/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'async_ui.dart';

void main() {
  testWidgets('Navegación vacía, alta sin foto y mensajes en español', (
    tester,
  ) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    late Directory root;
    late WardrobeRepository repo;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('wardrobe_ui_');
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
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        supportedLocales: const [Locale('es')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: WardrobeHome(repo: repo),
      ),
    );
    await waitForWidget(tester, find.text('Estrena tu armario virtual'));
    expect(find.text('Estrena tu armario virtual'), findsOneWidget);
    await tester.tap(find.text('Outfits'));
    await tester.pumpAndSettle();
    expect(find.text('Combina lo que ya tienes'), findsOneWidget);
    await tester.tap(find.text('Crear outfit'));
    await tester.pumpAndSettle();
    expect(
      find.text('Añade alguna prenda al armario antes de crear un outfit.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Calendario'));
    await tester.pumpAndSettle();
    expect(find.text('Qué me pongo'), findsOneWidget);
    await tester.tap(find.byTooltip('Más herramientas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copias de seguridad · exportar y restaurar'));
    await waitForWidget(tester, find.text('Exportar copia de seguridad'));
    expect(find.text('Exportar copia de seguridad'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Armario'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Añadir mi primera prenda'));
    await tester.pumpAndSettle();
    expect(find.text('Nueva prenda'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Camiseta');
    await tester.scrollUntilVisible(
      find.text('Guardar prenda'),
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar prenda'));
    await tester.pumpAndSettle();
    expect(find.text('Añade una foto de la prenda.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
