import 'auto_framed_photo.dart';
import 'backup_screen.dart';
import 'recommendation_service.dart';
import 'daily_tools_screen.dart';
import 'weather_service.dart';
import 'advanced_tools_screen.dart';
import 'outfit_image_service.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'models.dart';
import 'repository.dart';
import 'garment_editor.dart';
import 'outfit_editor.dart';
import 'ui_common.dart';
import 'batch_import_screen.dart';
import 'recommendations_screen.dart';
import 'wardrobe_tools.dart';
import 'wardrobe_tools_screen.dart';
import 'planned_calendar.dart';

class WardrobeHome extends StatefulWidget {
  final WardrobeRepository repo;
  const WardrobeHome({super.key, required this.repo});
  @override
  State<WardrobeHome> createState() => _WardrobeHomeState();
}

class _WardrobeHomeState extends State<WardrobeHome> {
  int tab = 0; // Armario es la pantalla inicial.
  bool loading = true, busy = false, onlyFavorites = false;
  String query = '',
      category = 'Todas',
      color = 'Todos',
      season = 'Todas',
      occasion = 'Todas',
      sortBy = 'Favoritas y nombre',
      availability = 'Todas',
      subtypeFilter = 'Todos';
  ClimatePreferences climatePreferences = const ClimatePreferences();
  WeatherForecast? todayForecast;
  String? undoLabel;
  Map<String, dynamic> reminder = {};
  List<Garment> garments = [];
  List<Outfit> outfits = [];
  List<DayPlan> plans = [];
  Map<String, WearStat> usage = {};
  DateTime selectedDay = DateUtils.dateOnly(DateTime.now());
  String? loadError;
  WardrobeRepository get repo => widget.repo;
  @override
  void initState() {
    super.initState();
    reload();
    WidgetsBinding.instance.addPostFrameCallback((_) => recoverPhoto());
  }

  Future<void> recoverPhoto() async {
    try {
      final lost = await ImagePicker().retrieveLostData();
      if (!mounted || lost.isEmpty) {
        return;
      }
      if (lost.files?.isNotEmpty ?? false) {
        message(
          context,
          'Se ha recuperado una foto pendiente. Completa la prenda para guardarla.',
        );
        await Navigator.push(
          context,
          MaterialPageRoute<bool>(
            builder: (_) => lost.files!.length > 1
                ? BatchImportScreen(repo: repo, files: lost.files!)
                : GarmentEditor(
                    repo: repo,
                    recoveredPhoto: lost.files!.first.path,
                  ),
          ),
        );
        if (mounted) {
          await reload();
        }
      } else if (lost.exception != null) {
        message(
          context,
          'No se pudo recuperar la última foto. Vuelve a añadirla.',
        );
      }
    } catch (_) {
      /* A fresh capture remains available from the editor. */
    }
  }

  Future<void> reload() async {
    try {
      final g = await repo.garments();
      final o = await repo.outfits();
      final d = await repo.plans();
      final u = await repo.usageStats();
      final climateData = ClimatePreferences.decode(
        await repo.setting('climate'),
      );
      final forecastData = WeatherForecast.decode(
        await repo.setting('weather_cache'),
      );
      final undoData = await repo.lastUndoLabel();
      final reminderData = Map<String, dynamic>.from(
        jsonDecode(await repo.setting('backup_reminder') ?? '{}') as Map,
      );
      if (mounted) {
        setState(() {
          climatePreferences = climateData;
          todayForecast = forecastData;
          undoLabel = undoData;
          garments = g;
          outfits = o;
          plans = d;
          usage = u;
          reminder = reminderData;
          loading = false;
          loadError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loadError = errorMessage(e);
          loading = false;
        });
      }
    }
  }

  Future<void> action(Future<void> Function() operation) async {
    if (busy) {
      return;
    }
    setState(() => busy = true);
    try {
      await operation();
      await reload();
    } catch (e) {
      if (mounted) {
        message(context, errorMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> importBatch() async {
    try {
      final files = await ImagePicker().pickMultiImage(
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
        limit: 30,
      );
      if (files.isEmpty || !mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BatchImportScreen(repo: repo, files: files),
        ),
      );
      if (mounted) await reload();
    } catch (_) {
      if (mounted) message(context, 'No se han podido seleccionar las fotos.');
    }
  }

  Future<void> openIdeas([String? anchorId]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecommendationsScreen(repo: repo, anchorId: anchorId),
      ),
    );
    if (mounted) await reload();
  }

  Future<void> editGarment([Garment? g]) async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    await Navigator.push(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => GarmentEditor(repo: repo, garment: g),
      ),
    );
    if (mounted) {
      await reload();
    }
  }

  Future<void> editOutfit([Outfit? o]) async {
    if (garments.isEmpty) {
      message(
        context,
        'Añade alguna prenda al armario antes de crear un outfit.',
      );
      return;
    }
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    await Navigator.push(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => OutfitEditor(repo: repo, garments: garments, outfit: o),
      ),
    );
    if (mounted) {
      await reload();
    }
  }

  List<Garment> get filteredGarments =>
      garments
          .where(
            (g) =>
                matchesGarmentSearch(g, query) &&
                (subtypeFilter == 'Todos' ||
                    (g.subtype.isEmpty
                            ? inferGarmentType(g.name)
                            : g.subtype) ==
                        subtypeFilter) &&
                (availability == 'Todas'
                    ? g.status != 'Archivada'
                    : g.status == availability) &&
                (category == 'Todas' ||
                    matchesCategoryGroup(category, roleOf(g))) &&
                (color == 'Todos' || g.colorTags.contains(color)) &&
                (season == 'Todas' ||
                    g.seasonTags.contains(season) ||
                    g.seasonTags.contains('Todo el año')) &&
                (occasion == 'Todas' || g.occasionTags.contains(occasion)) &&
                (!onlyFavorites || g.favorite),
          )
          .toList()
        ..sort((a, b) {
          if (sortBy == 'Menos usos registrados') {
            final diff = (usage[a.id]?.count ?? 0).compareTo(
              usage[b.id]?.count ?? 0,
            );
            if (diff != 0) return diff;
          }
          final favorites = (b.favorite ? 1 : 0).compareTo(a.favorite ? 1 : 0);
          return favorites != 0
              ? favorites
              : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
  Future<void> filters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, modalSet) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Filtrar armario',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  choice(
                    'Disponibilidad',
                    availability,
                    ['Todas', ...garmentStates],
                    (v) {
                      setState(() => availability = v);
                      modalSet(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  choice('Categoría', category, ['Todas', ...categories], (v) {
                    setState(() {
                      category = v;
                      subtypeFilter = 'Todos';
                    });
                    modalSet(() {});
                  }),
                  const SizedBox(height: 12),
                  choice(
                    'Tipo de prenda',
                    subtypeFilter,
                    [
                      'Todos',
                      ...garmentTypes.entries
                          .where(
                            (e) =>
                                category == 'Todas' ||
                                matchesCategoryGroup(category, e.value),
                          )
                          .map((e) => e.key),
                    ],
                    (v) {
                      setState(() => subtypeFilter = v);
                      modalSet(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  choice('Color', color, ['Todos', ...colors], (v) {
                    setState(() => color = v);
                    modalSet(() {});
                  }),
                  const SizedBox(height: 12),
                  choice('Temporada', season, ['Todas', ...seasons], (v) {
                    setState(() => season = v);
                    modalSet(() {});
                  }),
                  const SizedBox(height: 12),
                  choice('Ocasión', occasion, ['Todas', ...occasions], (v) {
                    setState(() => occasion = v);
                    modalSet(() {});
                  }),
                  const SizedBox(height: 12),
                  choice(
                    'Ordenar',
                    sortBy,
                    ['Favoritas y nombre', 'Menos usos registrados'],
                    (v) {
                      setState(() => sortBy = v);
                      modalSet(() {});
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Solo favoritas'),
                    value: onlyFavorites,
                    onChanged: (v) {
                      setState(() => onlyFavorites = v);
                      modalSet(() {});
                    },
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            category = 'Todas';
                            availability = 'Todas';
                            subtypeFilter = 'Todos';
                            color = 'Todos';
                            season = 'Todas';
                            occasion = 'Todas';
                            onlyFavorites = false;
                          });
                          Navigator.pop(context);
                        },
                        child: const Text('Limpiar filtros'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Ver prendas'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> garmentMenu(Garment g, String value) async {
    if (garmentStates.contains(value)) {
      await action(() => repo.batchUpdate({g.id}, {'status': value}));
      return;
    }
    if (value == 'suggest') {
      await openIdeas(g.id);
      return;
    }
    if (value == 'edit') {
      await editGarment(g);
      return;
    }
    final usage = await repo.garmentUsage(g.id);
    if (!mounted) {
      return;
    }
    if (usage > 0) {
      message(
        context,
        'Esta prenda aparece en $usage outfits. Quítala de ellos antes de eliminarla.',
      );
      return;
    }
    if (await confirm(
      context,
      'Eliminar prenda',
      'Se borrará «${g.name}» y su foto del armario.',
    )) {
      await action(() => repo.deleteGarment(g.id));
    }
  }

  Widget wardrobe() {
    final list = filteredGarments;
    return Column(
      children: [
        if (backupDue(reminder, DateTime.now(), hasData: garments.isNotEmpty))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: reminderBanner(),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => query = v),
                      decoration: const InputDecoration(
                        hintText: 'Buscar una prenda',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filledTonal(
                    onPressed: filters,
                    tooltip: 'Filtrar',
                    icon: const Icon(Icons.tune),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['Todas', ...categories]
                      .map(
                        (v) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(v),
                            selected: category == v,
                            onSelected: (_) => setState(() {
                              category = v;
                              subtypeFilter = 'Todos';
                            }),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? EmptyView(
                  icon: Icons.checkroom_outlined,
                  title: garments.isEmpty
                      ? 'Estrena tu armario virtual'
                      : 'Sin resultados',
                  subtitle: garments.isEmpty
                      ? 'Haz una foto de tu primera prenda o añádela desde la galería.'
                      : 'Prueba otra búsqueda o cambia los filtros.',
                  onAction: garments.isEmpty ? editGarment : null,
                  action: 'Añadir mi primera prenda',
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    childAspectRatio: .77,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final g = list[i];
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: Semantics(
                        label: g.name,
                        button: true,
                        child: InkWell(
                          onTap: () => editGarment(g),
                          onLongPress: () async {
                            final selected = await showModalBottomSheet<String>(
                              context: context,
                              showDragHandle: true,
                              builder: (c) => SafeArea(
                                child: ListView(
                                  shrinkWrap: true,
                                  children: [
                                    ListTile(
                                      title: Text(g.name),
                                      subtitle: Text(
                                        '${g.subtype.isEmpty ? g.category : g.subtype} · ${g.status}',
                                      ),
                                    ),
                                    ListTile(
                                      title: Text(
                                        g.favorite
                                            ? 'Quitar de favoritas'
                                            : 'Marcar favorita',
                                      ),
                                      onTap: () => Navigator.pop(c, 'favorite'),
                                    ),
                                    for (final state in garmentStates)
                                      ListTile(
                                        title: Text(state),
                                        onTap: () => Navigator.pop(c, state),
                                      ),
                                    ListTile(
                                      title: const Text(
                                        'Sugerir outfit con esta prenda',
                                      ),
                                      onTap: () => Navigator.pop(c, 'suggest'),
                                    ),
                                    ListTile(
                                      title: const Text('Editar'),
                                      onTap: () => Navigator.pop(c, 'edit'),
                                    ),
                                    ListTile(
                                      title: const Text('Eliminar'),
                                      onTap: () => Navigator.pop(c, 'delete'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                            if (selected == null) return;
                            if (selected == 'favorite') {
                              await action(
                                () => repo.favorite(
                                  'garments',
                                  g.id,
                                  !g.favorite,
                                ),
                              );
                            } else {
                              await garmentMenu(g, selected);
                            }
                          },
                          child: AutoFramedPhoto(repo.photoPath(g.photo)),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget outfitList() => outfits.isEmpty
      ? EmptyView(
          icon: Icons.style_outlined,
          title: 'Combina lo que ya tienes',
          subtitle: 'Crea un outfit con las prendas de tu armario y guárdalo para otro día.',
          onAction: editOutfit,
          action: 'Crear outfit',
        )
      : ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
          children: [
            Text(
              'Tus combinaciones',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text('${outfits.length} outfits guardados'),
            const SizedBox(height: 20),
            for (final o in outfits)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Card(
                  child: Column(
                    children: [
                      InkWell(
                        onTap: () => editOutfit(o),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: OutfitBoard(
                            repo: repo,
                            garments: garments,
                            items: o.items,
                          ),
                        ),
                      ),
                      if (o.referencePhoto.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: SizedBox(
                            height: 200,
                            child: Photo(
                              repo.photoPath(o.referencePhoto),
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ListTile(
                        title: Text(
                          o.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${o.occasion} · ${o.items.length} prendas',
                        ),
                        onTap: () => editOutfit(o),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: o.favorite
                                  ? 'Quitar de favoritos'
                                  : 'Marcar favorito',
                              onPressed: () => action(
                                () =>
                                    repo.favorite('outfits', o.id, !o.favorite),
                              ),
                              icon: Icon(
                                o.favorite
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                              ),
                            ),
                            PopupMenuButton<String>(
                              tooltip: 'Opciones del outfit',
                              onSelected: (v) async {
                                if (v == 'edit') {
                                  await editOutfit(o);
                                } else if (v == 'export') {
                                  await OutfitImageService.export(
                                    context,
                                    repo,
                                    o,
                                    garments,
                                  );
                                } else if (await confirm(
                                  context,
                                  'Eliminar outfit',
                                  'Se eliminará «${o.name}» y sus registros del calendario. Tus prendas se conservarán.',
                                )) {
                                  await action(() => repo.deleteOutfit(o.id));
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'export',
                                  child: Text('Exportar como imagen'),
                                ),
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Editar'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Eliminar'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
  Future<void> choosePlan() async {
    if (outfits.isEmpty) {
      message(context, 'Crea un outfit antes de planificarlo.');
      return;
    }
    final selected = await showModalBottomSheet<Outfit>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Elige un outfit',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            for (final o in outfits)
              ListTile(
                title: Text(o.name),
                subtitle: Text(o.occasion),
                leading: const Icon(Icons.style_outlined),
                onTap: () => Navigator.pop(context, o),
              ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      await action(
        () => repo.savePlan(DayPlan(dateKey(selectedDay), selected.id, false)),
      );
    }
  }

  Widget calendar() {
    final matching = plans.where((p) => p.date == dateKey(selectedDay));
    final plan = matching.isEmpty ? null : matching.first;
    final matchingOutfit = outfits.where((o) => o.id == plan?.outfitId);
    final outfit = matchingOutfit.isEmpty ? null : matchingOutfit.first;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Qué me pongo',
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Planifica un outfit por día y registra cuándo lo has usado.',
        ),
        PlannedCalendar(
          selected: selectedDay,
          plans: plans,
          onChanged: (d) => setState(() => selectedDay = d),
        ),
        Text(
          MaterialLocalizations.of(context).formatFullDate(selectedDay),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        if (outfit != null) ...[
          OutfitBoard(repo: repo, garments: garments, items: outfit.items),
          const SizedBox(height: 12),
          Text(outfit.name, style: Theme.of(context).textTheme.titleLarge),
          if (plan?.worn == true)
            TextButton.icon(
              icon: const Icon(Icons.rate_review_outlined),
              label: const Text('Valorar después de usarlo'),
              onPressed: () async {
                try {
                  await rateUsage(context, repo, plan!);
                } catch (e) {
                  if (mounted) message(context, errorMessage(e));
                }
              },
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Lo he usado este día'),
            value: plan!.worn,
            onChanged: selectedDay.isAfter(DateUtils.dateOnly(DateTime.now()))
                ? null
                : (v) => action(
                    () => repo.savePlan(DayPlan(plan.date, plan.outfitId, v)),
                  ),
          ),
          Row(
            children: [
              OutlinedButton(
                onPressed: choosePlan,
                child: const Text('Cambiar outfit'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => action(() => repo.deletePlan(plan.date)),
                child: const Text('Quitar'),
              ),
            ],
          ),
        ] else
          FilledButton.icon(
            onPressed: choosePlan,
            icon: const Icon(Icons.add),
            label: const Text('Asignar outfit'),
          ),
        const SizedBox(height: 28),
        Text('Días registrados', style: Theme.of(context).textTheme.titleLarge),
        if (plans.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Todavía no has planificado ningún día.'),
          ),
        for (final d in plans)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              d.worn ? Icons.check_circle_outline : Icons.event_outlined,
            ),
            title: Text(outfits.where((o) => o.id == d.outfitId).first.name),
            subtitle: Text(
              MaterialLocalizations.of(context)
                      .formatMediumDate(DateTime.parse(d.date)) +
                  (d.worn ? ' · Usado' : ' · Planificado'),
            ),
            onTap: () async {
              final date = DateTime.parse(d.date);
              setState(() => selectedDay = date);
              // Recreate CalendarDatePicker through its key when selecting another day.
            },
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> openTools() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WardrobeToolsScreen(repo: repo)),
    );
    if (mounted) await reload();
  }

  Future<void> saveReminder(Map<String, dynamic> value) async {
    await action(() async {
      await repo.saveSetting('backup_reminder', jsonEncode(value));
    });
  }

  Widget reminderBanner() => Card(
    child: ListTile(
      leading: const Icon(Icons.backup_outlined),
      title: const Text('Tu armario necesita una copia'),
      subtitle: const Text(
        'Exporta una copia al menos cada semana. Este aviso aparece al abrir la app; no es una notificación del sistema.',
      ),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => BackupScreen(repo: repo)),
        );
        await reload();
      },
      trailing: IconButton(
        tooltip: 'Recordar mañana',
        icon: const Icon(Icons.snooze),
        onPressed: () => saveReminder({
          ...reminder,
          'snooze_until': dateKey(calendarDayOffset(DateTime.now(), 1)),
        }),
      ),
    ),
  );
  Future<void> moreTools() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final e in {
              'advanced': 'Conjuntos, compras, historial y archivo',
              'wardrobe': 'Olvidadas, duplicados y maletas',
              'review': 'Fichas por revisar',
              'laundry': 'Prendas en lavado',
              'backup': 'Copias de seguridad · exportar y restaurar',
              'undo': 'Deshacer última acción',
            }.entries)
              ListTile(
                leading: Icon(switch (e.key) {
                  'advanced' => Icons.widgets_outlined,
                  'wardrobe' => Icons.checkroom_outlined,
                  'review' => Icons.fact_check_outlined,
                  'laundry' => Icons.local_laundry_service_outlined,
                  'backup' => Icons.cloud_upload_outlined,
                  _ => Icons.undo,
                }),
                title: Text(e.value),
                subtitle: e.key == 'undo' ? Text(undoLabel ?? 'Sin acciones pendientes') : null,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(c, e.key),
              ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    if (selected == 'undo') {
      await action(repo.undoLast);
      return;
    }
    if (selected == 'wardrobe') {
      await openTools();
      return;
    }
    if (selected == 'backup') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => BackupScreen(repo: repo)),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => selected == 'advanced'
              ? AdvancedToolsScreen(repo: repo)
              : DailyToolsScreen(repo: repo, laundry: selected == 'laundry'),
        ),
      );
    }
    await reload();
  }

  Future<void> chooseTodayOutfit() async {
    selectedDay = DateUtils.dateOnly(DateTime.now());
    await choosePlan();
  }

  Widget today() {
    final key = dateKey(DateTime.now());
    final plan = plans.where((p) => p.date == key).firstOrNull;
    final outfit = outfits.where((o) => o.id == plan?.outfitId).firstOrNull;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Hoy', style: Theme.of(context).textTheme.headlineLarge),
        Text(MaterialLocalizations.of(context).formatFullDate(DateTime.now())),
        const SizedBox(height: 20),
        if (outfit == null) ...[
          const Icon(Icons.checkroom_outlined, size: 58),
          const SizedBox(height: 12),
          Text('¿Qué te vas a poner?',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Elige un conjunto que ya hayas guardado o descubre una combinación nueva.',
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: chooseTodayOutfit,
            icon: const Icon(Icons.style_outlined),
            label: const Text('Elegir outfit guardado'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => openIdeas(),
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('Dame ideas nuevas'),
          ),
        ] else ...[
          Text('Tu outfit de hoy', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          OutfitBoard(repo: repo, garments: garments, items: outfit.items),
          const SizedBox(height: 12),
          Text(outfit.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: chooseTodayOutfit,
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Cambiar outfit'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: busy || plan!.worn ? null : () => action(() async {
              final pieces = garments.where((g) => outfit.items.any((i) => i.garmentId == g.id)).toList();
              await repo.savePlan(DayPlan(key, outfit.id, true));
              if (mounted) await offerLaundry(context, repo, pieces);
            }),
            icon: const Icon(Icons.check_circle_outline),
            label: Text(plan?.worn == true ? 'Uso registrado' : 'Lo he usado hoy'),
          ),
        ],
      ],
    );
  }

  bool sameWeatherCity(WeatherCity a, WeatherCity b) =>
      a.latitude == b.latitude && a.longitude == b.longitude;
  Widget ideas() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('Ideas para vestir', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      const Text('Descubre nuevas combinaciones de tu ropa, según tu estilo, la ocasión y el tiempo.'),
      const SizedBox(height: 20),
      Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openIdeas(),
          child: const Padding(
            padding: EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.auto_awesome, size: 36),
              SizedBox(height: 16),
              Text('Crear nuevas ideas', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Combina prendas, ajusta las preferencias y guarda tus propuestas favoritas.'),
              SizedBox(height: 18),
              Row(children: [Text('Explorar combinaciones'), Spacer(), Icon(Icons.arrow_forward)]),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () => openIdeas(),
        icon: const Icon(Icons.wb_sunny_outlined),
        label: const Text('Ideas según el tiempo y la ocasión'),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mi Armario',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Más herramientas',
            icon: const Icon(Icons.more_horiz),
            onPressed: busy ? null : moreTools,
          ),
          if (tab == 0)
            IconButton(
              tooltip: 'Añadir varias fotos',
              onPressed: busy ? null : importBatch,
              icon: const Icon(Icons.photo_library_outlined),
            ),
          if (tab == 0 || tab == 1)
            IconButton(
              tooltip: tab == 0 ? 'Añadir prenda' : 'Crear outfit',
              onPressed: busy
                  ? null
                  : () => tab == 0 ? editGarment() : editOutfit(),
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      body: Stack(
        children: [
          AbsorbPointer(
            absorbing: busy,
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : loadError != null
                ? EmptyView(
                    icon: Icons.error_outline,
                    title: 'No se pudo cargar el armario',
                    subtitle: loadError!,
                    onAction: reload,
                    action: 'Reintentar',
                  )
                : [wardrobe, outfitList, ideas, today, calendar][tab](),
          ),
          if (busy)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black26,
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          const Text('Procesando…'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: busy ? null : (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.checkroom_outlined), selectedIcon: Icon(Icons.checkroom), label: 'Armario'),
          NavigationDestination(icon: Icon(Icons.style_outlined), selectedIcon: Icon(Icons.style), label: 'Outfits'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'Ideas'),
          NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Hoy'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Calendario'),
        ],
      ),
    ),
  );
}
