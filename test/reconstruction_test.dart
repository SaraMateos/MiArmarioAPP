import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mi_armario/models.dart';
import 'package:mi_armario/repository.dart';
import 'package:mi_armario/recommendation_service.dart';
import 'package:mi_armario/advanced_data.dart';

void main() {
  late WardrobeRepository repo;
  late Directory dir;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('reconstruction_');
    repo = await WardrobeRepository.open(dir);
    final src = File('${dir.path}/src.jpg');
    await src.writeAsBytes([255, 216, 255, 217]);
    final photo = await repo.importPhoto(src.path);
    for (final id in ['top', 'bottom']) {
      await repo.saveGarment(
        Garment(
          id: id,
          name: id,
          category: id == 'top' ? 'Parte superior' : 'Parte inferior',
          subtype: id == 'top' ? 'Camiseta' : 'Pantalón',
          photo: photo,
        ),
      );
    }
    await repo.saveOutfit(
      Outfit(
        id: 'outfit',
        name: 'Outfit',
        items: [
          OutfitItem(garmentId: 'top', x: .2, y: .2, scale: 1),
          OutfitItem(garmentId: 'bottom', x: .5, y: .5, scale: 1),
        ],
      ),
    );
  });
  tearDown(() async {
    await repo.close();
    await dir.delete(recursive: true);
  });
  test(
    'Deshacer recupera el uso original aunque el outfit haya cambiado',
    () async {
      await repo.savePlan(const DayPlan('2026-10-01', 'outfit', true));
      await repo.deletePlan('2026-10-01');
      await repo.saveOutfit(
        Outfit(
          id: 'outfit',
          name: 'Editado',
          items: [OutfitItem(garmentId: 'top', x: .2, y: .2, scale: 1)],
        ),
      );
      await repo.undoLast();
      expect((await repo.plans()).single.worn, true);
      expect(
        (await repo.db.query('garment_wears'))
            .map((r) => r['garment_id'])
            .toSet(),
        {'top', 'bottom'},
      );
    },
  );
  test('Deshacer lote revierte todas las disponibilidades', () async {
    await repo.batchUpdate({'top', 'bottom'}, {'status': 'En lavado'});
    await repo.undoLast();
    expect((await repo.garments()).every((g) => g.available), true);
  });
  test('Deshacer impide sobrescribir una ficha editada después', () async {
    await repo.batchUpdate({'top'}, {'status': 'En lavado'});
    final g = (await repo.garments()).firstWhere((g) => g.id == 'top');
    await repo.saveGarment(
      Garment.fromMap({...g.toMap(), 'name': 'Nombre posterior'}),
    );
    await expectLater(repo.undoLast(), throwsFormatException);
    expect(
      (await repo.garments()).firstWhere((g) => g.id == 'top').name,
      'Nombre posterior',
    );
  });
  test('Deshacer avisa si el outfit anterior ya fue borrado', () async {
    await repo.savePlan(const DayPlan('2026-10-01', 'outfit', false));
    await repo.deletePlan('2026-10-01');
    await repo.deleteOutfit('outfit');
    await expectLater(repo.undoLast(), throwsFormatException);
    expect(await repo.plans(), isEmpty);
  });
  test('Se retienen diez acciones y se eliminan al restaurar', () async {
    for (var i = 0; i < 12; i++) {
      await repo.batchUpdate(
        {'top'},
        {'status': i.isEven ? 'En lavado' : 'Disponible'},
      );
    }
    expect((await repo.db.query('undo_actions')).length, 10);
    await repo.replaceData(await repo.snapshot());
    expect(await repo.lastUndoLabel(), isNull);
  });
  test('Deshacer semana elimina solo las asignaciones creadas', () async {
    final outfits = await repo.outfits();
    await repo.saveNewWeek({
      const DayPlan('2026-10-01', 'new', false): Outfit(
        id: 'new',
        name: 'Nuevo',
        items: outfits.single.items,
      ),
    });
    await repo.undoLast();
    expect(await repo.plans(), isEmpty);
    expect((await repo.outfits()).any((o) => o.id == 'new'), true);
  });
  test('Búsqueda combina campos y normaliza acentos', () {
    final g = Garment(
      id: 'g',
      name: 'Pantalón azul',
      category: 'Parte inferior',
      photo: 'g.jpg',
      details: {'brand': 'Marca Uno', 'fabric': 'Algodón', 'size': 'M'},
    );
    expect(matchesGarmentSearch(g, 'pantalon marca algodon'), true);
    expect(matchesGarmentSearch(g, 'pantalon seda'), false);
  });
  test(
    'Datos por revisar son válidos y exclusión fija da diagnóstico',
    () async {
      expect(validGarmentDetails({'needs_review': true}), true);
      final profile = RecommendationProfile(
        exclusions: {
          '2026-10-01': ['top'],
        },
      );
      expect(
        RecommendationService.noSuggestionReason(
          await repo.garments(),
          anchorId: 'top',
          profile: profile,
          date: DateTime(2026, 10, 1),
        ),
        contains('excluida'),
      );
    },
  );
  test('Grupos superiores incluyen exteriores sin cambiar sus roles', () {
    expect(
      typesForCategoryGroup('Parte superior'),
      containsAll(['Camiseta', 'Jersey', 'Abrigo', 'Chaqueta']),
    );
    expect(
      typesForCategoryGroup('Parte superior'),
      isNot(contains('Pantalón')),
    );
    expect(garmentTypes['Abrigo'], 'Abrigos');
    expect(matchesCategoryGroup('Parte inferior', 'Abrigos'), false);
  });
}
