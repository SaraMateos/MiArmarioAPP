import 'dart:convert';

import 'package:mi_armario/backup_screen.dart';

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mi_armario/home.dart';
import 'package:mi_armario/models.dart';
import 'package:mi_armario/repository.dart';
import 'package:mi_armario/garment_editor.dart';
import 'package:mi_armario/daily_tools_screen.dart';

import 'async_ui.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory root;
  late WardrobeRepository repo;
  late Garment garment;
  final boundary = GlobalKey();
  Future<void> prepare(WidgetTester t, {String status = 'Disponible'}) async {
    t.view.physicalSize = const Size(412, 892);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.runAsync(() async {
      final fonts = Platform.environment['ARMARIO_QA_FONTS'];
      if (fonts != null) {
        for (final f in [
          ('Roboto', 'Roboto-Regular.ttf'),
          ('MaterialIcons', 'MaterialIcons-Regular.otf'),
        ]) {
          final loader = FontLoader(f.$1);
          loader.addFont(
            File('$fonts/${f.$2}')
                .readAsBytes()
                .then((b) => ByteData.sublistView(b)),
          );
          await loader.load();
        }
      }
      root = await Directory.systemTemp.createTemp('daily_ui_');
      repo = await WardrobeRepository.open(root);
      garment = Garment(
        id: 'g',
        name: 'Pantalón azul',
        category: 'Parte inferior',
        subtype: 'Pantalón',
        status: status,
        photo: await repo.importPhoto('test/fixtures/pantalon.png'),
      );
      await repo.saveGarment(garment);
      final imageProvider = ResizeImage(
        FileImage(File(repo.photoPath(garment.photo))),
        width: 650,
      );
      final ready = Completer<void>();
      final stream = imageProvider.resolve(ImageConfiguration.empty);
      final listener = ImageStreamListener(
        (image, sync) {
          if (!ready.isCompleted) ready.complete();
        },
        onError: (Object e, StackTrace? s) {
          if (!ready.isCompleted) ready.completeError(e, s);
        },
      );
      stream.addListener(listener);
      await ready.future;
      stream.removeListener(listener);
    });
    addTearDown(() async {
      await repo.close();
      await root.delete(recursive: true);
    });
  }

  Future<void> launch(WidgetTester t, Widget page) async {
    await t.pumpWidget(
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
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
            filled: true,
          ),
        ),
        home: RepaintBoundary(key: boundary, child: page),
      ),
    );
  }

  Future<void> capture(WidgetTester t, String name) async {
    final folder = Platform.environment['ARMARIO_QA_DIR'];
    if (folder == null) return;
    for (var i = 0; i < 5; i++) {
      await t.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await t.pumpAndSettle();
    }
    await t.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(folder).create(recursive: true);
      await File('$folder/$name.png').writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('Hoy registra uso y permite posponer lavado', (t) async {
    await prepare(t);
    await t.runAsync(() async {
      await repo.saveOutfit(
        Outfit(
          id: 'o',
          name: 'Mi conjunto',
          items: [OutfitItem(garmentId: 'g')],
        ),
      );
      await repo.savePlan(DayPlan(dateKey(DateTime.now()), 'o', false));
    });
    await launch(t, WardrobeHome(repo: repo));
    await t.tap(find.text('Hoy'));
    await waitForWidget(t, find.text('Lo he usado hoy'));
    await t.pumpAndSettle();
    await waitForWidget(t, find.text('Lo he usado hoy'));
    await capture(t, 'hoy');
    await t.ensureVisible(find.text('Lo he usado hoy'));
    await t.tap(find.text('Lo he usado hoy'));
    for (
      var attempt = 0;
      attempt < 100 &&
          find.text('¿Enviar prendas a lavado?').evaluate().isEmpty;
      attempt++
    ) {
      await t.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await t.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('¿Enviar prendas a lavado?'), findsOneWidget);
    await t.tap(find.text('Ahora no'));
    await waitForWidget(t, find.text('Uso registrado'));
    await t.runAsync(() async {
      expect((await repo.plans()).single.worn, true);
      expect((await repo.garments()).single.available, true);
    });
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('Lavado selecciona y recupera disponibilidad', (t) async {
    await prepare(t, status: 'En lavado');
    await launch(t, DailyToolsScreen(repo: repo, laundry: true));
    await waitForWidget(t, find.text('Pantalón azul'));
    await t.tap(find.byType(CheckboxListTile).first);
    await t.pumpAndSettle();
    expect(find.text('Ya están limpias (1)'), findsOneWidget);
    await capture(t, 'lavado');
    await t.tap(find.text('Ya están limpias (1)'));
    await waitForWidget(t, find.text('No hay prendas pendientes.'));
    await t.runAsync(() async {
      expect((await repo.garments()).single.available, true);
      await repo.undoLast();
      expect((await repo.garments()).single.status, 'En lavado');
    });
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Detección dudosa permite confirmar pantalón sin aviso emergente',
    (t) async {
      await prepare(t);
      const channel = MethodChannel('es.personal.mi_armario/local_photo');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => {
              'category': 'Parte superior',
              'name': 'Camiseta',
              'confidence': .3,
              'colors': ['Azul'],
              'alternatives': ['Pantalón', 'Camiseta'],
            },
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await launch(
        t,
        GarmentEditor(
          repo: repo,
          recoveredPhoto: repo.photoPath(garment.photo),
        ),
      );
      await waitForWidget(t, find.text('Guardar prenda'));
      await t.scrollUntilVisible(
        find.textContaining('Por revisar'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      await capture(t, 'revisar_prenda');
      await t.tap(find.widgetWithText(ActionChip, 'Pantalón'));
      await t.pumpAndSettle();
      expect(find.text('Tipo confirmado por ti'), findsOneWidget);
      await t.tap(find.text('Guardar prenda'));
      var saved = false;
      var accepted = false;
      for (var attempt = 0; attempt < 100 && !saved; attempt++) {
        await t.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          saved = (await repo.garments()).length == 2;
        });
        await t.pump(const Duration(milliseconds: 20));
        if (!accepted &&
            find.text('Guardar igualmente').evaluate().isNotEmpty) {
          await t.tap(find.text('Guardar igualmente'));
          accepted = true;
        }
      }
      expect(saved, true);
      await t.runAsync(() async {
        final all = await repo.garments();
        expect(all, hasLength(2));
        expect(all.last.category, 'Parte inferior');
      });
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Inicio en Armario muestra fotos con filtros de categoría',
    (t) async {
      await prepare(t);
      await t.runAsync(() async {
        await repo.saveGarment(
          Garment(
            id: 'coat',
            name: 'Abrigo negro',
            category: 'Abrigos',
            subtype: 'Abrigo',
            photo: garment.photo,
          ),
        );
      });
      await launch(t, WardrobeHome(repo: repo));
      await waitForWidget(t, find.text('Buscar una prenda'));
      expect(find.text('Pantalón azul'), findsNothing);
      expect(find.text('Abrigo negro'), findsNothing);
      expect(find.bySemanticsLabel('Abrigo negro'), findsOneWidget);
      await t.tap(find.text('Parte superior'));
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel('Abrigo negro'), findsOneWidget);
      expect(find.bySemanticsLabel('Pantalón azul'), findsNothing);
      await capture(t, 'armario_solo_fotos');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Copias guarda y muestra el cambio de recordatorio en su propia pantalla',
    (t) async {
      await prepare(t);
      await launch(t, BackupScreen(repo: repo));
      await waitForWidget(t, find.text('Exportar copia de seguridad'));
      final reminder = find.text('Recordar copia semanal al abrir la app');
      await t.scrollUntilVisible(
        reminder,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await t.ensureVisible(find.byType(Switch));
      await t.pumpAndSettle();
      await t.tap(find.byType(Switch));
      for (
        var attempt = 0;
        attempt < 250 && t.widget<Switch>(find.byType(Switch)).value;
        attempt++
      ) {
        await t.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await t.pump();
      }
      expect(t.widget<Switch>(find.byType(Switch)).value, false);
      await t.runAsync(() async {
        expect(
          jsonDecode((await repo.setting('backup_reminder'))!)['enabled'],
          false,
        );
      });
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Revisión permite ampliar foto y desplegar colores sin solapamientos',
    (t) async {
      await prepare(t);
      await launch(t, GarmentEditor(repo: repo, garment: garment));
      await t.pumpAndSettle();
      await t.tap(find.byType(Image).first);
      await t.pumpAndSettle();
      expect(find.text('Revisar foto'), findsOneWidget);
      expect(
        t.widget<InteractiveViewer>(find.byType(InteractiveViewer)).maxScale,
        4,
      );
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      final section = find.text('Colores, temporadas y ocasiones');
      await t.scrollUntilVisible(
        section,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(section);
      await t.pumpAndSettle();
      final red = find.widgetWithText(FilterChip, 'Rojo');
      await t.scrollUntilVisible(
        red,
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(red, findsOneWidget);
      await t.tap(red);
      await t.pumpAndSettle();
      await capture(t, 'colores_desplegados');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
}
