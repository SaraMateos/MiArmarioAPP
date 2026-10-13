import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mi_armario/models.dart';
import 'package:mi_armario/repository.dart';
import 'package:mi_armario/backup_service.dart';
import 'package:mi_armario/recommendation_service.dart';
import 'package:mi_armario/weather_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory root;
  late WardrobeRepository repo;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('wardrobe_v11_');
    repo = await WardrobeRepository.open(root);
  });
  tearDown(() async {
    await repo.close();
    await root.delete(recursive: true);
  });
  Future<Garment> add(
    String id, {
    String category = 'Parte superior',
    int warmth = 2,
  }) async {
    final source = File('${root.path}/source.png');
    await source.writeAsBytes([1, 2, 3]);
    final photo = await repo.importPhoto(source.path);
    final g = Garment(
      id: id,
      name: id,
      category: category,
      photo: photo,
      colorTags: ['Blanco', 'Azul'],
      seasonTags: ['Primavera', 'Otoño'],
      occasionTags: ['Diario', 'Trabajo'],
      warmth: warmth,
    );
    await repo.saveGarment(g);
    return g;
  }

  test(
    'Selecciones múltiples sobreviven al guardado y copia/restauración',
    () async {
      await add('g1');
      final stored = (await repo.garments()).single;
      expect(stored.colorTags, ['Blanco', 'Azul']);
      expect(stored.seasonTags, ['Primavera', 'Otoño']);
      expect(stored.occasionTags, ['Diario', 'Trabajo']);
      await BackupService(repo).restore(await BackupService(repo).export());
      expect((await repo.garments()).single.colorTags, ['Blanco', 'Azul']);
    },
  );
  test(
    'Historial de uso conserva las prendas reales aunque se edite el outfit',
    () async {
      await add('g1');
      await add('g2');
      final day = dateKey(DateTime.now());
      await repo.saveOutfit(
        Outfit(
          id: 'o1',
          name: 'Outfit',
          items: [OutfitItem(garmentId: 'g1')],
        ),
      );
      await repo.savePlan(DayPlan(day, 'o1', true));
      await repo.saveOutfit(
        Outfit(
          id: 'o1',
          name: 'Editado',
          items: [OutfitItem(garmentId: 'g2')],
        ),
      );
      await repo.savePlan(DayPlan(day, 'o1', true));
      expect((await repo.usageStats())['g1']?.count, 1);
      expect((await repo.usageStats())['g2'], null);
      await repo.savePlan(DayPlan(day, 'o1', false));
      expect(await repo.usageStats(), isEmpty);
      await repo.savePlan(DayPlan(day, 'o1', true));
      expect((await repo.usageStats())['g2']?.count, 1);
      await repo.deleteOutfit('o1');
      expect(await repo.usageStats(), isEmpty);
    },
  );
  test(
    'Copia 1.0 migra colores, ocasiones y usos sin perder fotografías',
    () async {
      final g = await add('g1');
      final day = dateKey(DateTime.now());
      final legacy = {
        'garments': [
          {
            'id': 'g1',
            'name': 'Original',
            'category': 'Parte superior',
            'color': 'Blanco',
            'season': 'Verano',
            'occasion': 'Diario',
            'notes': '',
            'photo': g.photo,
            'favorite': 1,
          },
        ],
        'outfits': [
          {
            'id': 'o1',
            'name': 'Original',
            'occasion': 'Trabajo',
            'notes': '',
            'favorite': 0,
          },
        ],
        'outfit_items': [
          {
            'outfit_id': 'o1',
            'garment_id': 'g1',
            'position': 0,
            'x': .2,
            'y': .3,
            'scale': 1.0,
          },
        ],
        'plans': [
          {'date': day, 'outfit_id': 'o1', 'worn': 1},
        ],
      };
      final manifest = utf8.encode(
        jsonEncode({'format': 'mi_armario', 'version': 1, 'data': legacy}),
      );
      final bytes = await File(repo.photoPath(g.photo)).readAsBytes();
      final archive = Archive()
        ..addFile(ArchiveFile('manifest.json', manifest.length, manifest))
        ..addFile(ArchiveFile('photos/${g.photo}', bytes.length, bytes));
      await BackupService(repo)
          .restore(Uint8List.fromList(ZipEncoder().encode(archive)));
      final result = (await repo.garments()).single;
      expect(result.name, 'Original');
      expect(result.colorTags, ['Blanco']);
      expect(result.seasonTags, ['Verano']);
      expect(result.warmth, 2);
      expect((await repo.usageStats())['g1']?.count, 1);
      expect((await repo.outfits()).single.occasionTags, ['Trabajo']);
    },
  );
  test('Planificación de varios días revierte toda la operación si un día ya existe', () async {
    await add('g1');
    await repo.saveOutfit(
      Outfit(
        id: 'existing',
        name: 'Existente',
        items: [OutfitItem(garmentId: 'g1')],
      ),
    );
    final today = DateTime.now(),
        d1 = dateKey(today),
        d2 = dateKey(today.add(const Duration(days: 1)));
    await repo.savePlan(DayPlan(d2, 'existing', false));
    final o1 = Outfit(
      id: 'new1',
      name: 'Nuevo 1',
      items: [OutfitItem(garmentId: 'g1')],
    );
    final o2 = Outfit(
      id: 'new2',
      name: 'Nuevo 2',
      items: [OutfitItem(garmentId: 'g1')],
    );
    await expectLater(
      repo.saveNewWeek({
        DayPlan(d1, 'new1', false): o1,
        DayPlan(d2, 'new2', false): o2,
      }),
      throwsFormatException,
    );
    expect((await repo.outfits()).map((o) => o.id), ['existing']);
    expect((await repo.plans()).single.outfitId, 'existing');
  });
  test(
    'Recomendaciones respetan la prenda base y evitan conjuntos incompletos',
    () async {
      final top = await add('top'),
          bottom = await add('bottom', category: 'Parte inferior'),
          shoe = await add('shoe', category: 'Calzado');
      final all = [top, bottom, shoe];
      final results = RecommendationService.suggest(
        garments: all,
        usage: {},
        date: DateTime.now(),
        climate: Climate.mild,
        anchorId: bottom.id,
      );
      expect(results, isNotEmpty);
      for (final s in results) {
        expect(s.garments.any((g) => g.id == bottom.id), true);
        expect(s.garments.map((g) => g.id).toSet().length, s.garments.length);
      }
      expect(
        RecommendationService.suggest(
          garments: [shoe],
          usage: {},
          date: DateTime.now(),
          climate: Climate.hot,
        ),
        isEmpty,
      );
    },
  );
  test(
    'Se favorece una prenda poco utilizada y se añade abrigo con frío',
    () async {
      final rare = await add('rare', warmth: 3),
          recent = await add('recent', warmth: 3);
      final bottom = await add('bottom', category: 'Parte inferior', warmth: 3),
          coat = await add('coat', category: 'Abrigos', warmth: 3);
      final today = DateTime.now();
      final results = RecommendationService.suggest(
        garments: [rare, recent, bottom, coat],
        usage: {
          recent.id: WearStat(
            count: 20,
            lastWorn: today.subtract(const Duration(days: 1)),
          ),
        },
        date: today,
        climate: Climate.cold,
      );
      expect(results.first.garments.any((g) => g.id == rare.id), true);
      expect(results.first.garments.any((g) => g.id == coat.id), true);
    },
  );
  test('Un abrigo ligero no se puntúa como uno abrigado con frío', () async {
    final top = await add('top', warmth: 1);
    final bottom = await add('bottom', category: 'Parte inferior', warmth: 1);
    final light = await add('light_coat', category: 'Abrigos', warmth: 1);
    final warm = await add('warm_coat', category: 'Abrigos', warmth: 3);
    final result = RecommendationService.suggest(
      garments: [top, bottom, light, warm],
      usage: {},
      date: DateTime.now(),
      climate: Climate.cold,
      limit: 1,
    );
    expect(result.first.garments.any((g) => g.id == warm.id), true);
  });
  test('La semana mantiene siete fechas civiles únicas al cambiar la hora', () {
    final start = DateTime(2026, 10, 25);
    final dates = List.generate(7, (i) => dateKey(calendarDayOffset(start, i)));
    expect(dates, [
      '2026-10-25',
      '2026-10-26',
      '2026-10-27',
      '2026-10-28',
      '2026-10-29',
      '2026-10-30',
      '2026-10-31',
    ]);
    expect(
      calendarDayDifference(DateTime(2026, 3, 30), DateTime(2026, 3, 29)),
      1,
    );
  });
  test('Consulta meteorológica envía solo ciudad y coordenadas, y permite errores claros', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.host == 'geocoding-api.open-meteo.com') {
        return http.Response(
          jsonEncode({
            'results': [
              {
                'name': 'Madrid',
                'admin1': 'Madrid',
                'country': 'España',
                'latitude': 40.4,
                'longitude': -3.7,
              },
            ],
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'daily': {
            'time': ['2026-10-12'],
            'temperature_2m_min': [12],
            'temperature_2m_max': [22],
          },
        }),
        200,
      );
    });
    final service = WeatherService(client: client);
    final cities = await service.search('Madrid');
    final forecast = await service.fetch(cities.first);
    expect(forecast.days.single.climate, Climate.mild);
    expect(requests.every((r) => r.method == 'GET' && r.body.isEmpty), true);
    expect(requests.last.url.queryParameters['latitude'], '40.4');
    expect(WeatherForecast.decode(forecast.encode())?.days.single.max, 22);
    service.close();
    final failed = WeatherService(
      client: MockClient((_) async => http.Response('', 503)),
    );
    await expectLater(failed.fetch(cities.first), throwsFormatException);
    failed.close();
  });
}
