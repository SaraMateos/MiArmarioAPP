import 'category_outfit_view.dart';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'advanced_data.dart';
import 'models.dart';
import 'repository.dart';
import 'ui_common.dart';
import 'garment_editor.dart';

Future<void> rateUsage(
  BuildContext context,
  WardrobeRepository repo,
  DayPlan plan,
) async {
  if (!plan.worn) return;
  final rating = await showDialog<String>(
    context: context,
    builder: (c) => SimpleDialog(
      title: const Text('¿Cómo te sentiste con este outfit?'),
      children: [
        for (final r in [
          'Cómodo',
          'Pasé frío',
          'Demasiado abrigado',
          'No me convenció',
        ])
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, r),
            child: Text(r),
          ),
      ],
    ),
  );
  if (rating == null) return;
  final rows = await repo.db.query(
    'garment_wears',
    where: 'date = ?',
    whereArgs: [plan.date],
  );
  final current = (await repo.plans()).where(
    (p) => p.date == plan.date && p.worn && p.outfitId == plan.outfitId,
  );
  if (current.isEmpty) return;
  final entries = readEntries(await repo.setting('usage_feedback'))
    ..removeWhere((e) => e['id'] == plan.date);
  entries.add({
    'id': plan.date,
    'outfit_id': plan.outfitId,
    'items': rows.map((r) => r['garment_id'] as String).toList(),
    'rating': rating,
    'notes': '',
  });
  await repo.saveSetting(
    'usage_feedback',
    writeEntries(
      entries.length > 150 ? entries.sublist(entries.length - 150) : entries,
    ),
  );
  if (context.mounted) {
    message(context, 'Valoración guardada. Se tendrá en cuenta en Ideas.');
  }
}

Future<void> offerLaundry(
  BuildContext context,
  WardrobeRepository repo,
  List<Garment> pieces,
) async {
  final selected = pieces
      .where((g) => g.status == 'Disponible')
      .map((g) => g.id)
      .toSet();
  final accept = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, update) => AlertDialog(
        title: const Text('¿Enviar prendas a lavado?'),
        content: SizedBox(
          width: 330,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final g in pieces)
                  CheckboxListTile(
                    title: Text(g.name),
                    value: selected.contains(g.id),
                    onChanged: (v) => update(() {
                      if (v == true) {
                        selected.add(g.id);
                      } else {
                        selected.remove(g.id);
                      }
                    }),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Enviar seleccionadas'),
          ),
        ],
      ),
    ),
  );
  if (accept == true) await repo.batchUpdate(selected, {'status': 'En lavado'});
}

class AdvancedToolsScreen extends StatefulWidget {
  final WardrobeRepository repo;
  const AdvancedToolsScreen({super.key, required this.repo});
  @override
  State<AdvancedToolsScreen> createState() => _AdvancedToolsScreenState();
}

class _AdvancedToolsScreenState extends State<AdvancedToolsScreen> {
  List<Garment> garments = [];
  List<DayPlan> plans = [];
  List<Outfit> outfits = [];
  List<Map<String, dynamic>> sets = [], shopping = [], feedback = [];
  Map<String, List<String>> wornPhotos = {};
  bool busy = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      garments = await widget.repo.garments();
      plans = await widget.repo.plans();
      outfits = await widget.repo.outfits();
      sets = readEntries(await widget.repo.setting('linked_sets'));
      shopping = readEntries(await widget.repo.setting('shopping'));
      feedback = readEntries(await widget.repo.setting('usage_feedback'));
      wornPhotos = {};
      for (final row in await widget.repo.db.query(
        'garment_wears',
        orderBy: 'date, garment_id',
      )) {
        wornPhotos
            .putIfAbsent(row['date'] as String, () => [])
            .add(row['garment_id'] as String);
      }
    } catch (e) {
      if (mounted) message(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save(String key, List<Map<String, dynamic>> entries) async {
    try {
      await widget.repo.saveSetting(key, writeEntries(entries));
      await load();
    } catch (e) {
      if (mounted) message(context, errorMessage(e));
    }
  }

  Widget _thumbnails(List<String> ids) => SizedBox(
    width: 88,
    height: 64,
    child: Row(
      children: [
        for (final id in ids.take(2))
          Expanded(
            child: Photo(
              widget.repo.photoPath(
                garments.where((g) => g.id == id).firstOrNull?.photo ?? '',
              ),
              fit: BoxFit.contain,
            ),
          ),
      ],
    ),
  );
  Future<void> addSet() async {
    final name = TextEditingController();
    final ids = <String>{};
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('Prendas que van juntas'),
          content: SizedBox(
            width: 360,
            height: 400,
            child: Column(
              children: [
                TextField(
                  controller: name,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del conjunto',
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final g in garments.where(
                        (g) => g.status != 'Archivada',
                      ))
                        CheckboxListTile(
                          secondary: SizedBox.square(
                            dimension: 64,
                            child: Photo(widget.repo.photoPath(g.photo)),
                          ),
                          title: Text(g.name),
                          subtitle: Text(
                            g.subtype.isEmpty ? g.category : g.subtype,
                          ),
                          value: ids.contains(g.id),
                          onChanged: (v) => update(() {
                            if (v == true) {
                              ids.add(g.id);
                            } else {
                              ids.remove(g.id);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Vincular'),
            ),
          ],
        ),
      ),
    );
    final text = name.text.trim();
    name.dispose();
    if (yes != true) return;
    if (text.isEmpty || ids.length < 2 || ids.length > 10) {
      if (mounted) {
        message(context, 'Pon un nombre y elige entre 2 y 10 prendas.');
      }
      return;
    }
    if (sets.length >= 150 ||
        sets.any((s) => (s['items'] as List).any(ids.contains))) {
      if (mounted) {
        message(
          context,
          'Una prenda solo puede estar en un conjunto vinculado. Desvincúlala primero.',
        );
      }
      return;
    }
    await save('linked_sets', [
      ...sets,
      {'id': const Uuid().v4(), 'name': text, 'items': ids.toList()},
    ]);
  }

  Future<void> addShopping() async {
    final name = TextEditingController(), notes = TextEditingController();
    String category = categories.first, color = colors.first;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('Compra pendiente'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Qué necesitas'),
                ),
                choice(
                  'Categoría',
                  category,
                  categories,
                  (v) => update(() => category = v),
                ),
                const SizedBox(height: 12),
                choice('Color', color, colors, (v) => update(() => color = v)),
                TextField(
                  controller: notes,
                  maxLength: 300,
                  decoration: const InputDecoration(labelText: 'Notas'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Añadir'),
            ),
          ],
        ),
      ),
    );
    final n = name.text.trim(), note = notes.text.trim();
    name.dispose();
    notes.dispose();
    if (yes != true) return;
    if (n.isEmpty || shopping.length >= 150) {
      if (mounted) {
        message(
          context,
          'Escribe un nombre. La lista admite hasta 150 compras.',
        );
      }
      return;
    }
    await save('shopping', [
      ...shopping,
      {
        'id': const Uuid().v4(),
        'name': n,
        'category': category,
        'color': color,
        'notes': note,
      },
    ]);
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Más herramientas'),
        actions: [
          IconButton(
            tooltip: 'Edición por lotes',
            icon: const Icon(Icons.playlist_add_check),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BulkEditScreen(repo: widget.repo),
                ),
              );
              await load();
            },
          ),
        ],
        bottom: const TabBar(
          isScrollable: true,
          tabs: [
            Tab(text: 'Conjuntos'),
            Tab(text: 'Compras'),
            Tab(text: 'Historial'),
            Tab(text: 'Archivo'),
          ],
        ),
      ),
      body: busy
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'Si Ideas incluye una prenda vinculada, debe incluir el conjunto completo y disponible. Vincula piezas de funciones distintas; dos pantalones no forman una propuesta automática.',
                    ),
                    FilledButton.icon(
                      onPressed: addSet,
                      icon: const Icon(Icons.link),
                      label: const Text('Vincular prendas'),
                    ),
                    for (final s in sets)
                      Card(
                        child: ListTile(
                          leading: _thumbnails(
                            (s['items'] as List).cast<String>(),
                          ),
                          title: Text(s['name'] as String),
                          subtitle: Text(
                            (s['items'] as List)
                                .map(
                                  (id) =>
                                      garments
                                          .where((g) => g.id == id)
                                          .firstOrNull
                                          ?.name ??
                                      'Prenda eliminada',
                                )
                                .join(' + '),
                          ),
                          trailing: IconButton(
                            tooltip: 'Desvincular',
                            icon: const Icon(Icons.link_off),
                            onPressed: () => save(
                              'linked_sets',
                              sets.where((e) => e['id'] != s['id']).toList(),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    FilledButton.icon(
                      onPressed: addShopping,
                      icon: const Icon(Icons.add_shopping_cart),
                      label: const Text('Añadir compra pendiente'),
                    ),
                    for (final s in shopping)
                      Card(
                        child: ExpansionTile(
                          title: Text(s['name'] as String),
                          subtitle: Text('${s['category']} · ${s['color']}'),
                          children: [
                            if (s['notes'] != '')
                              ListTile(title: Text(s['notes'] as String)),
                            const ListTile(
                              title: Text('Prendas parecidas que ya tienes'),
                              subtitle: Text(
                                'Coincidencia de categoría y color; revisa si cubren lo que necesitas.',
                              ),
                            ),
                            if (!garments.any(
                              (g) =>
                                  g.status != 'Archivada' &&
                                  roleOf(g) == s['category'] &&
                                  g.colorTags.contains(s['color']),
                            ))
                              const ListTile(
                                title: Text(
                                  'No hay coincidencias en tu armario activo.',
                                ),
                              ),
                            for (final g in garments.where(
                              (g) =>
                                  g.status != 'Archivada' &&
                                  roleOf(g) == s['category'] &&
                                  g.colorTags.contains(s['color']),
                            ))
                              ListTile(
                                leading: SizedBox.square(
                                  dimension: 50,
                                  child: Photo(widget.repo.photoPath(g.photo)),
                                ),
                                title: Text(g.name),
                                subtitle: Text(g.status),
                              ),
                            TextButton(
                              onPressed: () => save(
                                'shopping',
                                shopping
                                    .where((e) => e['id'] != s['id'])
                                    .toList(),
                              ),
                              child: const Text('Quitar de pendientes'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (!plans.any((p) => p.worn))
                      const Text(
                        'Marca un outfit como usado en Ideas o Calendario para verlo aquí.',
                      ),
                    for (final p in plans.where((p) => p.worn))
                      Card(
                        child: ExpansionTile(
                          leading: _thumbnails(wornPhotos[p.date] ?? []),
                          title: Text(
                            '${p.date} · ${outfits.where((o) => o.id == p.outfitId).firstOrNull?.name ?? 'Outfit'}',
                          ),
                          subtitle: Text(
                            feedback
                                        .where((f) => f['id'] == p.date)
                                        .firstOrNull?['rating']
                                    as String? ??
                                'Sin valoración',
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: CategoryOutfitView(
                                repo: widget.repo,
                                garments: garments
                                    .where(
                                      (g) => (wornPhotos[p.date] ?? [])
                                          .contains(g.id),
                                    )
                                    .toList(),
                              ),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.rate_review_outlined),
                              label: const Text('Valorar este uso'),
                              onPressed: () async {
                                try {
                                  await rateUsage(context, widget.repo, p);
                                  await load();
                                } catch (e) {
                                  if (context.mounted) {
                                    message(context, errorMessage(e));
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'Las prendas archivadas conservan sus fotos, outfits e historial. Restaura su disponibilidad desde la ficha.',
                    ),
                    for (final g in garments.where(
                      (g) => g.status == 'Archivada',
                    ))
                      ListTile(
                        leading: SizedBox.square(
                          dimension: 50,
                          child: Photo(widget.repo.photoPath(g.photo)),
                        ),
                        title: Text(g.name),
                        subtitle: Text(
                          g.details['archive_reason'] as String? ?? '',
                        ),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  GarmentEditor(repo: widget.repo, garment: g),
                            ),
                          );
                          await load();
                        },
                      ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BulkEditScreen(repo: widget.repo),
                          ),
                        );
                        await load();
                      },
                      icon: const Icon(Icons.playlist_add_check),
                      label: const Text('Edición rápida de varias prendas'),
                    ),
                  ],
                ),
              ],
            ),
    ),
  );
}

class BulkEditScreen extends StatefulWidget {
  final WardrobeRepository repo;
  const BulkEditScreen({super.key, required this.repo});
  @override
  State<BulkEditScreen> createState() => _BulkEditScreenState();
}

class _BulkEditScreenState extends State<BulkEditScreen> {
  List<Garment> garments = [];
  final selected = <String>{};
  String type = 'Sin cambiar', status = 'Sin cambiar';
  List<String> selectedSeasons = ['Todo el año'];
  bool changeSeasons = false, busy = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      garments = await widget.repo.garments();
    } catch (e) {
      if (mounted) message(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> apply() async {
    if (selected.isEmpty) return;
    final fields = <String, Object?>{
      if (type != 'Sin cambiar') 'subtype': type,
      if (type != 'Sin cambiar') 'category': garmentTypes[type],
      if (status != 'Sin cambiar') 'status': status,
    };
    if (changeSeasons) fields['season'] = selectedSeasons;
    setState(() => busy = true);
    try {
      await widget.repo.batchUpdate(selected, fields);
      if (mounted) {
        message(context, '${selected.length} prendas actualizadas.');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        message(context, errorMessage(e));
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Edición por lotes')),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed:
              busy ||
                  selected.isEmpty ||
                  (type == 'Sin cambiar' &&
                      status == 'Sin cambiar' &&
                      !changeSeasons)
              ? null
              : apply,
          child: Text('Aplicar a ${selected.length} prendas'),
        ),
      ),
    ),
    body: busy
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Solo se cambian los campos que elijas. Los demás datos y fotos se conservan.',
              ),
              choice('Tipo', type, [
                'Sin cambiar',
                ...garmentTypes.keys,
              ], (v) => setState(() => type = v)),
              const SizedBox(height: 12),
              choice('Disponibilidad', status, [
                'Sin cambiar',
                ...garmentStates,
              ], (v) => setState(() => status = v)),
              SwitchListTile(
                title: const Text('Cambiar temporadas'),
                value: changeSeasons,
                onChanged: (v) => setState(() => changeSeasons = v),
              ),
              if (changeSeasons)
                MultiChoice(
                  label: 'Temporadas',
                  values: seasons,
                  selected: selectedSeasons,
                  exclusiveAllYear: true,
                  onChanged: (v) => setState(() => selectedSeasons = v),
                ),
              TextButton(
                onPressed: () => setState(() {
                  if (selected.length == garments.length) {
                    selected.clear();
                  } else {
                    selected.addAll(garments.map((g) => g.id));
                  }
                }),
                child: const Text('Seleccionar / desmarcar todas'),
              ),
              for (final g in garments)
                CheckboxListTile(
                  secondary: SizedBox.square(
                    dimension: 48,
                    child: Photo(widget.repo.photoPath(g.photo)),
                  ),
                  title: Text(g.name),
                  subtitle: Text(
                    '${g.subtype.isEmpty ? g.category : g.subtype} · ${g.status}',
                  ),
                  value: selected.contains(g.id),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      selected.add(g.id);
                    } else {
                      selected.remove(g.id);
                    }
                  }),
                ),
            ],
          ),
  );
}
