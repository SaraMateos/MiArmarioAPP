import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'repository.dart';
import 'wardrobe_tools.dart';
import 'recommendation_service.dart';
import 'recommendations_screen.dart';
import 'garment_editor.dart';
import 'ui_common.dart';

class WardrobeToolsScreen extends StatefulWidget {
  final WardrobeRepository repo;
  const WardrobeToolsScreen({super.key, required this.repo});
  @override
  State<WardrobeToolsScreen> createState() => _WardrobeToolsScreenState();
}

class _WardrobeToolsScreenState extends State<WardrobeToolsScreen> {
  List<Garment> garments = [];
  Map<String, WearStat> usage = {};
  List<Map<String, dynamic>> bags = [];
  List<DuplicatePair> duplicates = [];
  bool loading = true, scanning = false, scanned = false;
  int progress = 0, failed = 0;
  Future<void> load() async {
    try {
      final g = await widget.repo.garments(),
          u = await widget.repo.usageStats();
      final stored = jsonDecode(
        await widget.repo.setting('suitcases') ?? '{"bags":[]}',
      ) as Map;
      if (mounted) {
        setState(() {
          garments = g;
          usage = u;
          bags = (stored['bags'] as List)
              .map((b) => Map<String, dynamic>.from(b as Map))
              .toList();
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        message(context, errorMessage(e));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> scan() async {
    setState(() {
      scanning = true;
      progress = 0;
      failed = 0;
    });
    final hashes = <String, String>{};
    for (final g in garments) {
      if (!mounted) return;
      try {
        hashes[g.id] = await DuplicateService.fingerprint(
          widget.repo.photoPath(g.photo),
        );
      } catch (_) {
        failed++;
      }
      if (mounted) setState(() => progress++);
    }
    if (mounted) {
      setState(() {
        duplicates = DuplicateService.compare(garments, hashes);
        scanning = false;
        scanned = true;
      });
    }
  }

  Future<void> persistBags() async {
    final value = jsonEncode({'bags': bags});
    if (value.length > 50000) {
      throw const FormatException('La lista de maletas es demasiado grande.');
    }
    await widget.repo.saveSetting('suitcases', value);
  }

  Future<void> editBag([Map<String, dynamic>? bag]) async {
    if (bag == null && bags.length >= 20) {
      message(context, 'Puedes guardar hasta 20 maletas.');
      return;
    }
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => SuitcaseEditor(
          repo: widget.repo,
          garments: garments,
          usage: usage,
          bag: bag,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final old = [...bags];
    setState(() {
      bags.removeWhere((b) => b['id'] == result['id']);
      bags.add(result);
    });
    try {
      await persistBags();
    } catch (e) {
      if (mounted) {
        setState(() => bags = old);
        message(context, errorMessage(e));
      }
    }
  }

  Widget duplicateCard(DuplicatePair pair) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          const Text('Fotos parecidas · revisar'),
          Row(
            children: [
              for (final g in [pair.first, pair.second])
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              GarmentEditor(repo: widget.repo, garment: g),
                        ),
                      );
                      if (mounted) {
                        await load();
                        if (mounted) await scan();
                      }
                    },
                    child: Column(
                      children: [
                        SizedBox(
                          height: 150,
                          child: Photo(
                            widget.repo.photoPath(g.photo),
                            fit: BoxFit.contain,
                          ),
                        ),
                        Text(g.name),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Aprovecha tu armario'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Olvidadas'),
            Tab(text: 'Duplicados'),
            Tab(text: 'Maletas'),
          ],
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'Prendas disponibles sin uso registrado o sin usar en los últimos 30 días. Solo cuentan los días marcados como usados en la app.',
                    ),
                    const SizedBox(height: 12),
                    if (forgottenGarments(
                      garments,
                      usage,
                      DateTime.now(),
                    ).isEmpty)
                      const Text(
                        'No hay prendas disponibles olvidadas según tu historial.',
                      ),
                    for (final g in forgottenGarments(
                      garments,
                      usage,
                      DateTime.now(),
                    ))
                      Card(
                        child: ListTile(
                          leading: SizedBox(
                            width: 54,
                            height: 64,
                            child: Photo(widget.repo.photoPath(g.photo)),
                          ),
                          title: Text(g.name),
                          subtitle: Text(
                            usage[g.id]?.lastWorn == null
                                ? 'Sin usos registrados'
                                : 'Último uso: ${dateKey(usage[g.id]!.lastWorn!)}',
                          ),
                          trailing: const Icon(Icons.auto_awesome),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => RecommendationsScreen(
                                  repo: widget.repo,
                                  anchorId: g.id,
                                ),
                              ),
                            );
                            if (mounted) await load();
                          },
                        ),
                      ),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'Compara el aspecto de las fotos, categoría y colores. Son posibles duplicados: no se elimina ni fusiona nada automáticamente. Fondos o encuadres diferentes pueden ocultar coincidencias.',
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: scanning ? null : scan,
                      icon: const Icon(Icons.find_in_page_outlined),
                      label: Text(
                        scanning
                            ? 'Analizando $progress / ${garments.length}'
                            : 'Buscar posibles duplicados',
                      ),
                    ),
                    if (scanning) const LinearProgressIndicator(),
                    if (scanned && duplicates.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No se encontraron fotos parecidas con estos criterios.',
                        ),
                      ),
                    if (failed > 0)
                      Text('$failed fotos no pudieron analizarse.'),
                    for (final pair in duplicates) duplicateCard(pair),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    FilledButton.icon(
                      onPressed: () => editBag(),
                      icon: const Icon(Icons.luggage),
                      label: const Text('Preparar maleta'),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Guarda fechas y prendas; marca lo que ya has metido. Puedes incorporar outfits o pedir una lista orientativa para el viaje.',
                    ),
                    for (final bag in bags)
                      Card(
                        child: ListTile(
                          title: Text(bag['name'] as String),
                          subtitle: Text(
                            '${bag['start']} – ${bag['end']} · ${(bag['packed'] as List).length}/${(bag['items'] as List).length} preparado',
                          ),
                          onTap: () => editBag(bag),
                          trailing: IconButton(
                            tooltip: 'Eliminar maleta',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              if (await confirm(
                                context,
                                'Eliminar maleta',
                                'Se elimina la lista; tus prendas y outfits se conservan.',
                              )) {
                                final old = [...bags];
                                if (!mounted) return;
                                setState(() => bags.remove(bag));
                                try {
                                  await persistBags();
                                } catch (e) {
                                  if (mounted) {
                                    setState(() => bags = old);
                                    message(this.context, errorMessage(e));
                                  }
                                }
                              }
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
    ),
  );
}

class SuitcaseEditor extends StatefulWidget {
  final WardrobeRepository repo;
  final List<Garment> garments;
  final Map<String, WearStat> usage;
  final Map<String, dynamic>? bag;
  const SuitcaseEditor({
    super.key,
    required this.repo,
    required this.garments,
    required this.usage,
    this.bag,
  });
  @override
  State<SuitcaseEditor> createState() => _SuitcaseEditorState();
}

class _SuitcaseEditorState extends State<SuitcaseEditor> {
  late TextEditingController name;
  late DateTime start, end;
  late Set<String> selected, packed;
  Climate climate = Climate.mild;
  String occasion = 'Diario';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    final b = widget.bag;
    name = TextEditingController(text: b?['name'] as String? ?? '');
    start =
        DateTime.tryParse(b?['start'] as String? ?? '') ??
        DateUtils.dateOnly(DateTime.now());
    end =
        DateTime.tryParse(b?['end'] as String? ?? '') ??
        calendarDayOffset(start, 6);
    selected = (b?['items'] as List? ?? []).cast<String>().toSet();
    packed = (b?['packed'] as List? ?? []).cast<String>().toSet();
    occasion = b?['occasion'] as String? ?? 'Diario';
    climate = Climate.values.firstWhere(
      (c) => c.name == b?['climate'],
      orElse: () => Climate.mild,
    );
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> dates() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange: DateTimeRange(start: start, end: end),
    );
    if (range != null && mounted) {
      setState(() {
        start = range.start;
        end = range.end;
      });
    }
  }

  Future<void> addOutfit() async {
    final outfits = await widget.repo.outfits();
    if (!mounted) return;
    final chosen = await showModalBottomSheet<Outfit>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          children: [
            const ListTile(title: Text('Añadir prendas de un outfit')),
            if (outfits.isEmpty)
              const ListTile(title: Text('Todavía no hay outfits guardados.')),
            for (final o in outfits)
              ListTile(
                title: Text(o.name),
                onTap: () => Navigator.pop(context, o),
              ),
          ],
        ),
      ),
    );
    if (chosen != null && mounted) {
      setState(() => selected.addAll(chosen.items.map((i) => i.garmentId)));
    }
  }

  Future<void> suggest() async {
    final days = calendarDayDifference(end, start) + 1;
    if (days > 30) {
      message(
        context,
        'Las sugerencias de viaje admiten hasta 30 días. Puedes elegir prendas manualmente para viajes más largos.',
      );
      return;
    }
    setState(() => busy = true);
    try {
      final preferences = StylePreferences.decode(
        await widget.repo.setting('style_preferences'),
      );
      final virtual = Map<String, WearStat>.from(widget.usage),
          proposed = <String>{};
      for (var i = 0; i < days; i++) {
        final day = calendarDayOffset(start, i),
            list = RecommendationService.suggest(
              garments: widget.garments,
              usage: virtual,
              date: day,
              climate: climate,
              occasion: occasion,
              preferences: preferences,
              seed: i,
              limit: 1,
            );
        if (list.isEmpty) continue;
        for (final g in list.first.garments) {
          proposed.add(g.id);
          final old = virtual[g.id] ?? const WearStat();
          virtual[g.id] = WearStat(count: old.count + 1, lastWorn: day);
        }
      }
      if (mounted) {
        setState(() => selected.addAll(proposed));
        message(
          context,
          proposed.isEmpty
              ? 'Faltan prendas disponibles para sugerir conjuntos.'
              : 'Lista orientativa añadida. Revisa cantidades, lavado y el tiempo del destino.',
        );
      }
    } catch (e) {
      if (mounted) message(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void save() {
    if (name.text.trim().isEmpty || selected.isEmpty) {
      message(context, 'Pon nombre a la maleta y añade alguna prenda.');
      return;
    }
    if (selected.length > 300) {
      message(context, 'Máximo 300 prendas por maleta.');
      return;
    }
    Navigator.pop(context, {
      'id': widget.bag?['id'] ?? const Uuid().v4(),
      'name': name.text.trim(),
      'start': dateKey(start),
      'end': dateKey(end),
      'items': selected.toList(),
      'packed': packed.intersection(selected).toList(),
      'occasion': occasion,
      'climate': climate.name,
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Preparar maleta')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: busy ? null : save,
            child: const Text('Guardar maleta'),
          ),
        ),
      ),
      body: AbsorbPointer(
        absorbing: busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: name,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Nombre del viaje'),
            ),
            OutlinedButton.icon(
              onPressed: dates,
              icon: const Icon(Icons.date_range),
              label: Text('${dateKey(start)} – ${dateKey(end)}'),
            ),
            choice(
              'Temperatura del destino',
              climate.label,
              Climate.values.map((c) => c.label).toList(),
              (v) => setState(
                () => climate = Climate.values.firstWhere((c) => c.label == v),
              ),
            ),
            const SizedBox(height: 12),
            choice(
              'Ocasión',
              occasion,
              occasions,
              (v) => setState(() => occasion = v),
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: addOutfit,
                  icon: const Icon(Icons.style),
                  label: const Text('Añadir outfit'),
                ),
                TextButton.icon(
                  onPressed: suggest,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Sugerir ropa'),
                ),
              ],
            ),
            if (busy) const LinearProgressIndicator(),
            Text(
              '${packed.intersection(selected).length}/${selected.length} prendas preparadas. Guarda para conservar los cambios.',
            ),
            for (final id in selected.where(
              (id) => !widget.garments.any((g) => g.id == id),
            ))
              ListTile(
                title: const Text('Prenda eliminada del armario'),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() {
                    selected.remove(id);
                    packed.remove(id);
                  }),
                ),
              ),
            for (final g in widget.garments)
              Card(
                child: ListTile(
                  leading: Checkbox(
                    value: selected.contains(g.id),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        selected.add(g.id);
                      } else {
                        selected.remove(g.id);
                        packed.remove(g.id);
                      }
                    }),
                  ),
                  title: Text(g.name),
                  subtitle: Text(g.status),
                  trailing: selected.contains(g.id)
                      ? IconButton(
                          tooltip: packed.contains(g.id)
                              ? 'Sacar de la maleta'
                              : 'Marcar como preparada',
                          icon: Icon(
                            packed.contains(g.id)
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                          ),
                          onPressed: () => setState(() {
                            if (!packed.add(g.id)) packed.remove(g.id);
                          }),
                        )
                      : null,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
