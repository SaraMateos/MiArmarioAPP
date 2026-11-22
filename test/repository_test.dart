import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_armario/backup_service.dart';
import 'package:mi_armario/models.dart';
import 'package:mi_armario/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory root;
  late WardrobeRepository repo;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('wardrobe_test_');
    repo = await WardrobeRepository.open(root);
  });
  tearDown(() async {
    await repo.close();
    await root.delete(recursive: true);
  });
  Future<Garment> addGarment(String id) async {
    final source = File('${root.path}/source.jpg');
    await source.writeAsBytes([255, 216, 255, 217]);
    final photo = await repo.importPhoto(source.path);
    final g = Garment(
      id: id,
      name: 'Camiseta blanca',
      category: categories.first,
      color: 'Blanco',
      season: seasons.first,
      occasion: occasions.first,
      photo: photo,
    );
    await repo.saveGarment(g);
    return g;
  }

  test(
    'Editar una prenda conserva referencias y calendario; borrado protegido',
    () async {
      final g = await addGarment('g1');
      final o = Outfit(
        id: 'o1',
        name: 'Diario',
        occasion: 'Diario',
        items: [OutfitItem(garmentId: g.id, x: .4, y: .6, scale: 1.2)],
      );
      await repo.saveOutfit(o);
      await repo.savePlan(const DayPlan('2026-10-12', 'o1', true));
      await repo.saveGarment(
        Garment(
          id: g.id,
          name: 'Camiseta editada',
          category: g.category,
          color: g.color,
          season: g.season,
          occasion: g.occasion,
          photo: g.photo,
        ),
      );
      expect((await repo.outfits()).single.items.single.garmentId, 'g1');
      expect((await repo.plans()).single.worn, true);
      await expectLater(repo.deleteGarment('g1'), throwsFormatException);
      await repo.deleteOutfit('o1');
      expect(await repo.plans(), isEmpty);
      await repo.deleteGarment('g1');
      expect(await repo.garments(), isEmpty);
      expect(await File(repo.photoPath(g.photo)).exists(), false);
    },
  );
  test(
    'Editar un outfit conserva su planificación y actualiza composición',
    () async {
      await addGarment('g1');
      await addGarment('g2');
      await repo.saveOutfit(
        Outfit(
          id: 'o1',
          name: 'Outfit',
          occasion: 'Diario',
          items: [OutfitItem(garmentId: 'g1')],
        ),
      );
      await repo.savePlan(const DayPlan('2026-10-12', 'o1', false));
      await repo.saveOutfit(
        Outfit(
          id: 'o1',
          name: 'Nuevo',
          occasion: 'Trabajo',
          items: [OutfitItem(garmentId: 'g2', x: .7, y: .8, scale: 1.3)],
        ),
      );
      expect((await repo.plans()).single.outfitId, 'o1');
      expect((await repo.outfits()).single.items.single.x, .7);
    },
  );
  test(
    'Exportar y restaurar conserva fotos, composición, favoritos y calendario',
    () async {
      await addGarment('g1');
      await repo.favorite('garments', 'g1', true);
      await repo.saveOutfit(
        Outfit(
          id: 'o1',
          name: 'Trabajo',
          occasion: 'Trabajo',
          items: [
            OutfitItem(
              garmentId: 'g1',
              x: .5,
              y: .7,
              scale: 1.9,
              mannequinX: .4,
              mannequinY: .6,
              mannequinScale: 1.1,
            ),
          ],
          favorite: true,
        ),
      );
      await repo.savePlan(const DayPlan('2026-10-12', 'o1', true));
      final bytes = await BackupService(repo).export();
      final originalPhoto = (await repo.garments()).single.photo;
      await addGarment('extra');
      await BackupService(repo).restore(bytes);
      final g = (await repo.garments()).single;
      expect(g.favorite, true);
      expect(g.photo, isNot(originalPhoto));
      expect(await File(repo.photoPath(g.photo)).readAsBytes(), [
        255,
        216,
        255,
        217,
      ]);
      final item = (await repo.outfits()).single.items.single;
      expect((item.x, item.y, item.scale), (.5, .7, 1.9));
      expect(
        (item.mannequinX, item.mannequinY, item.mannequinScale),
        (.4, .6, 1.1),
      );
      expect((await repo.plans()).single.worn, true);
      expect(await File(repo.photoPath(originalPhoto)).exists(), false);
    },
  );
  test('Restaura también los ZIP de formato 5 creados con la 1.7.7', () async {
    await addGarment('g1');
    await repo.saveOutfit(
      Outfit(
        id: 'o1',
        name: 'Anterior',
        items: [
          OutfitItem(
            garmentId: 'g1',
            mannequinX: .4,
            mannequinY: .6,
            mannequinScale: 1.2,
          ),
        ],
      ),
    );
    final archive = ZipDecoder().decodeBytes(
      await BackupService(repo).export(),
    );
    final originalManifest = archive.findFile('manifest.json')!;
    final original = jsonDecode(utf8.decode(originalManifest.content)) as Map;
    original['version'] = 5;

    Uint8List legacyZip() {
      final manifest = utf8.encode(jsonEncode(original));
      final zip = Archive()
        ..addFile(ArchiveFile('manifest.json', manifest.length, manifest));
      for (final file in archive.files.where(
        (f) => f.name != 'manifest.json',
      )) {
        zip.addFile(file);
      }
      return Uint8List.fromList(ZipEncoder().encode(zip));
    }

    await BackupService(repo).restore(legacyZip());
    var item = (await repo.outfits()).single.items.single;
    expect(
      (item.mannequinX, item.mannequinY, item.mannequinScale),
      (.4, .6, 1.2),
    );

    final row = (original['data']['outfit_items'] as List).single as Map;
    row['mannequin_x'] = .3;
    row['mannequin_y'] = .2;
    row['mannequin_scale'] = 1;
    await BackupService(repo).restore(legacyZip());
    item = (await repo.outfits()).single.items.single;
    expect(item.mannequinX, OutfitItem.unsetMannequinX);

    row.remove('mannequin_x');
    await expectLater(
      BackupService(repo).restore(legacyZip()),
      throwsFormatException,
    );
    row.remove('mannequin_y');
    row.remove('mannequin_scale');
    await BackupService(repo).restore(legacyZip());
    item = (await repo.outfits()).single.items.single;
    expect(item.mannequinX, OutfitItem.unsetMannequinX);
  });

  test(
    'Copia incompleta no reemplaza datos ni borra las fotos originales',
    () async {
      final g = await addGarment('g1');
      final manifest = utf8.encode(
        jsonEncode({
          'format': 'mi_armario',
          'version': 5,
          'data': await repo.snapshot(),
        }),
      );
      final zip = Archive()
        ..addFile(ArchiveFile('manifest.json', manifest.length, manifest));
      await expectLater(
        BackupService(repo)
            .restore(Uint8List.fromList(ZipEncoder().encode(zip))),
        throwsFormatException,
      );
      expect((await repo.garments()).single.id, g.id);
      expect(await File(repo.photoPath(g.photo)).exists(), true);
    },
  );
  test(
    'Rechaza rutas fuera de photos, datos inválidos y versiones desconocidas',
    () async {
      await addGarment('g1');
      final zip = Archive()
        ..addFile(ArchiveFile('../escape.jpg', 3, [1, 2, 3]));
      await expectLater(
        BackupService(repo)
            .restore(Uint8List.fromList(ZipEncoder().encode(zip))),
        throwsFormatException,
      );
      final data = await repo.snapshot();
      expect(
        () => BackupService.validateManifest({
          'format': 'mi_armario',
          'version': 99,
          'data': data,
        }),
        throwsFormatException,
      );
      final changed = jsonDecode(jsonEncode(data)) as Map;
      changed['garments'][0]['photo'] = '../../wardrobe.db';
      expect(
        () => BackupService.validateManifest({
          'format': 'mi_armario',
          'version': 5,
          'data': changed,
        }),
        throwsFormatException,
      );
      expect(await repo.garments(), hasLength(1));
    },
  );
  test(
    'Transacción fallida durante reemplazo conserva todos los datos anteriores',
    () async {
      final g = await addGarment('g1');
      final data = await repo.snapshot();
      final mutable = Map<String, List<Map<String, Object?>>>.from(data);
      mutable['garments'] = [g.toMap(), g.toMap()];
      await expectLater(
        repo.replaceData(mutable),
        throwsA(isA<DatabaseException>()),
      );
      expect((await repo.garments()).single.id, 'g1');
      expect(await File(repo.photoPath(g.photo)).exists(), true);
    },
  );
  test(
    'Duplicados en el ZIP original se rechazan antes de cambiar datos',
    () async {
      final g = await addGarment('g1');
      final manifest = utf8.encode(
        jsonEncode({
          'format': 'mi_armario',
          'version': 5,
          'data': await repo.snapshot(),
        }),
      );
      final archive = Archive()
        ..addFile(ArchiveFile('manifest.json', manifest.length, manifest))
        ..addFile(ArchiveFile('photos/a.jpg', 3, [1, 2, 3]))
        ..addFile(ArchiveFile('photos/b.jpg', 3, [1, 2, 3]));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
      final needle = utf8.encode('photos/b.jpg');
      final replacement = utf8.encode('photos/a.jpg');
      for (var i = 0; i <= bytes.length - needle.length; i++) {
        if (List.generate(
          needle.length,
          (j) => bytes[i + j] == needle[j],
        ).every((v) => v)) {
          bytes.setRange(i, i + replacement.length, replacement);
        }
      }
      await expectLater(
        BackupService(repo).restore(bytes),
        throwsFormatException,
      );
      expect((await repo.garments()).single.id, g.id);
    },
  );
}
