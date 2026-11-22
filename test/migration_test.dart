import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mi_armario/models.dart';
import 'package:mi_armario/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test(
    'Actualización de SQLite 1 a 7 preserva IDs, relaciones y uso anterior',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final root = await Directory.systemTemp.createTemp('wardrobe_schema1_');
      final db = await openDatabase(
        '${root.path}/wardrobe.db',
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE garments(id TEXT PRIMARY KEY, name TEXT NOT NULL, category TEXT NOT NULL, color TEXT NOT NULL, season TEXT NOT NULL, occasion TEXT NOT NULL, notes TEXT NOT NULL, photo TEXT NOT NULL, favorite INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE outfits(id TEXT PRIMARY KEY, name TEXT NOT NULL, occasion TEXT NOT NULL, notes TEXT NOT NULL, favorite INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE outfit_items(outfit_id TEXT NOT NULL REFERENCES outfits(id) ON DELETE CASCADE, garment_id TEXT NOT NULL REFERENCES garments(id) ON DELETE RESTRICT, position INTEGER NOT NULL, x REAL NOT NULL, y REAL NOT NULL, scale REAL NOT NULL, PRIMARY KEY(outfit_id,garment_id))',
          );
          await db.execute(
            'CREATE TABLE plans(date TEXT PRIMARY KEY,outfit_id TEXT NOT NULL REFERENCES outfits(id) ON DELETE CASCADE,worn INTEGER NOT NULL)',
          );
        },
      );
      await db.insert('garments', {
        'id': 'g1',
        'name': 'Anterior',
        'category': 'Parte superior',
        'color': 'Azul',
        'season': 'Invierno',
        'occasion': 'Trabajo',
        'notes': '',
        'photo': 'original.png',
        'favorite': 1,
      });
      await db.insert('outfits', {
        'id': 'o1',
        'name': 'Outfit anterior',
        'occasion': 'Diario',
        'notes': '',
        'favorite': 0,
      });
      await db.insert('outfit_items', {
        'outfit_id': 'o1',
        'garment_id': 'g1',
        'position': 0,
        'x': .3,
        'y': .4,
        'scale': .8,
      });
      await db.insert('plans', {
        'date': dateKey(DateTime.now()),
        'outfit_id': 'o1',
        'worn': 1,
      });
      await db.close();
      final repo = await WardrobeRepository.open(root);
      try {
        expect((await repo.garments()).single.colorTags, ['Azul']);
        final item = (await repo.outfits()).single.items.single;
        expect((item.x, item.y, item.scale), (.3, .4, .8));
        expect(item.mannequinX, OutfitItem.unsetMannequinX);
        expect((await repo.usageStats())['g1']?.count, 1);
        expect(
          jsonDecode(
            (await repo.db.query('garments')).single['color'] as String,
          ),
          ['Azul'],
        );
        expect(await repo.db.getVersion(), 7);
      } finally {
        await repo.close();
        await root.delete(recursive: true);
      }
    },
  );
  test('Migración de SQLite 6 conserva los maniquíes editados', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final root = await Directory.systemTemp.createTemp('wardrobe_schema6_');
    var repo = await WardrobeRepository.open(root);
    final photo = await repo.importPhoto('test/fixtures/camiseta.png');
    await repo.saveGarment(
      Garment(
        id: 'g1',
        name: 'Camiseta',
        category: 'Parte superior',
        photo: photo,
      ),
    );
    await repo.saveGarment(
      Garment(
        id: 'g2',
        name: 'Segunda camiseta',
        category: 'Parte superior',
        photo: photo,
      ),
    );
    final defaultItem = OutfitItem(garmentId: 'g1', mannequinX: .3);
    await repo.saveOutfit(
      Outfit(id: 'legacy', name: 'Anterior', items: [defaultItem]),
    );
    await repo.saveOutfit(
      Outfit(
        id: 'edited',
        name: 'Editado',
        items: [
          defaultItem,
          OutfitItem(garmentId: 'g2', mannequinX: .45, mannequinY: .65),
        ],
      ),
    );
    await repo.db.setVersion(6);
    await repo.close();
    repo = await WardrobeRepository.open(root);
    try {
      final outfits = {
        for (final outfit in await repo.outfits()) outfit.id: outfit,
      };
      expect(
        outfits['legacy']!.items.single.mannequinX,
        OutfitItem.unsetMannequinX,
      );
      expect(outfits['edited']!.items.map((i) => i.mannequinX), [.3, .45]);
      expect(await repo.db.getVersion(), 7);
    } finally {
      await repo.close();
      await root.delete(recursive: true);
    }
  });
}
