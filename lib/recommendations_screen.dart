import 'advanced_data.dart';
import 'advanced_tools_screen.dart';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'repository.dart';
import 'recommendation_service.dart';
import 'weather_service.dart';
import 'outfit_editor.dart';
import 'ui_common.dart';
import 'category_outfit_view.dart';
import 'wardrobe_tools.dart';
import 'outfit_draft_screen.dart';
import 'week_editor.dart';
import 'garment_editor.dart';

class RecommendationsScreen extends StatefulWidget {
  final WardrobeRepository repo;
  final String? anchorId;
  const RecommendationsScreen({super.key, required this.repo, this.anchorId});
  @override
  State<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends State<RecommendationsScreen> {
  final weather = WeatherService();
  final cityQuery = TextEditingController();
  List<Garment> garments = [];
  Map<String, WearStat> usage = {};
  List<OutfitSuggestion> suggestions = [];
  StylePreferences style = StylePreferences();
  RecommendationProfile profile = RecommendationProfile();
  List<Map<String, dynamic>> feedback = [];
  ClimatePreferences preferences = const ClimatePreferences();
  WeatherForecast? forecast;
  String occasion = 'Diario', error = '';
  DateTime date = DateUtils.dateOnly(DateTime.now());
  int seed = 0;
  bool busy = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    weather.close();
    cityQuery.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      garments = await widget.repo.garments();
      usage = await widget.repo.usageStats();
      style = StylePreferences.decode(
        await widget.repo.setting('style_preferences'),
      );
      preferences = ClimatePreferences.decode(
        await widget.repo.setting('climate'),
      );
      forecast = WeatherForecast.decode(
        await widget.repo.setting('weather_cache'),
      );
      profile = RecommendationProfile.decode(
        await widget.repo.setting('recommendation_profile'),
      );
      profile.linkedSets = readEntries(await widget.repo.setting('linked_sets'))
          .map((s) => (s['items'] as List).cast<String>())
          .toList();
      feedback = readEntries(await widget.repo.setting('usage_feedback'))
          .where(
            (f) => (f['id'] as String).compareTo(dateKey(DateTime.now())) <= 0,
          )
          .toList();
      await generate();
    } catch (e) {
      if (mounted) setState(() => error = errorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  bool sameCity(WeatherCity a, WeatherCity b) =>
      a.latitude == b.latitude && a.longitude == b.longitude;
  Future<void> updateForecast() async {
    final city = preferences.city;
    if (city == null) {
      throw const FormatException(
        'Selecciona una ciudad o utiliza el modo manual.',
      );
    }
    if (forecast != null &&
        forecast!.isFresh &&
        sameCity(forecast!.city, city)) {
      return;
    }
    forecast = await weather.fetch(city);
    await widget.repo.saveSetting('weather_cache', forecast!.encode());
  }

  Climate climateFor(DateTime day) {
    if (!preferences.automatic) return preferences.manual;
    final item = forecast?.forDate(day);
    if (item == null) {
      throw const FormatException(
        'No hay previsión para ese día. Utiliza el modo manual.',
      );
    }
    return item.climate;
  }

  bool rainyFor(DateTime day) => preferences.automatic
      ? (forecast?.forDate(day)?.rainProbability ?? 0) >= 50
      : profile.rain;
  bool windyFor(DateTime day) => preferences.automatic
      ? (forecast?.forDate(day)?.windSpeed ?? 0) >= 30
      : profile.wind;
  Future<void> excludePieces() async {
    final selected = profile.excludedOn(date);
    final accept = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: Text('Excluir solo el ${dateKey(date)}'),
          content: SizedBox(
            width: 360,
            height: 350,
            child: ListView(
              children: [
                for (final g in garments.where((g) => g.available))
                  CheckboxListTile(
                    secondary: SizedBox.square(
                      dimension: 64,
                      child: Photo(widget.repo.photoPath(g.photo)),
                    ),
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
    if (accept == true) {
      profile.exclusions[dateKey(date)] = selected.toList();
      await generate();
    }
  }

  Future<void> markUsed(OutfitSuggestion suggestion) async {
    if (busy || dateKey(date) != dateKey(DateTime.now())) return;
    setState(() => busy = true);
    try {
      final known = await widget.repo.outfits();
      final previous = (await widget.repo.plans())
          .where((p) => p.date == dateKey(date))
          .firstOrNull;
      Outfit? outfit = known
          .where(
            (o) =>
                (o.items.map((i) => i.garmentId).toList()..sort()).join('|') ==
                suggestion.signature,
          )
          .firstOrNull;
      if (previous != null &&
          previous.outfitId != outfit?.id &&
          mounted &&
          !await confirm(
            context,
            'Cambiar outfit de hoy',
            'Se sustituirá el outfit del día y su registro de uso.',
            action: 'Registrar este',
          )) {
        return;
      }
      if (!mounted) return;
      outfit ??= Outfit(
        id: const Uuid().v4(),
        name: 'Usado · ${dateKey(date)}',
        occasion: occasion,
        items: suggestion.items,
        notes: suggestion.reasons.join('. '),
      );
      await widget.repo.saveOutfit(outfit);
      final plan = DayPlan(dateKey(date), outfit.id, true);
      await widget.repo.savePlan(plan);
      if (mounted) message(context, 'Outfit registrado como usado hoy.');
      if (mounted) {
        await offerLaundry(context, widget.repo, suggestion.garments);
      }
      if (mounted) await rateUsage(context, widget.repo, plan);
      garments = await widget.repo.garments();
      usage = await widget.repo.usageStats();
      feedback = readEntries(await widget.repo.setting('usage_feedback'));
      await generate();
    } catch (e) {
      if (mounted) message(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> generate() async {
    if (mounted) {
      setState(() {
        busy = true;
        error = '';
      });
    }
    try {
      profile.exclusions.removeWhere(
        (key, _) => key.compareTo(dateKey(DateTime.now())) < 0,
      );
      await widget.repo.saveSetting('recommendation_profile', profile.encode());
      await widget.repo.saveSetting('climate', preferences.encode());
      if (preferences.automatic) await updateForecast();
      final result = RecommendationService.suggest(
        garments: garments,
        usage: usage,
        date: date,
        climate: climateFor(date),
        occasion: occasion,
        anchorId: widget.anchorId,
        preferences: style,
        profile: profile,
        rainy: rainyFor(date),
        windy: windyFor(date),
        feedback: feedback,
        seed: seed,
      );
      if (mounted) setState(() => suggestions = result);
    } catch (e) {
      if (mounted) {
        setState(() {
          suggestions = [];
          error = errorMessage(e);
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> rate(OutfitSuggestion s, bool liked) async {
    try {
      style.rate(s.garments, liked);
      await widget.repo.saveSetting('style_preferences', style.encode());
      if (!mounted) return;
      message(
        context,
        liked ? 'Preferencia guardada en el móvil.' : 'Evitaremos esta combinación. Puedes restablecer tus preferencias.',
      );
      await generate();
    } catch (e) {
      if (mounted) message(context, errorMessage(e));
    }
  }

  Future<void> chooseCity() async {
    List<WeatherCity> results = [];
    bool searching = false;
    String cityError = '';
    final selected = await showModalBottomSheet<WeatherCity>(
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
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .55,
              child: Column(
                children: [
                  const Text(
                    'Consultar tiempo por ciudad',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: cityQuery,
                    decoration: const InputDecoration(labelText: 'Ciudad'),
                    textInputAction: TextInputAction.search,
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: searching
                        ? null
                        : () async {
                            modalSet(() {
                              searching = true;
                              cityError = '';
                            });
                            try {
                              final found = await weather.search(
                                cityQuery.text,
                              );
                              if (context.mounted) {
                                modalSet(() => results = found);
                              }
                            } catch (_) {
                              if (context.mounted) {
                                modalSet(
                                  () => cityError = 'No se ha podido buscar. Comprueba la conexión.',
                                );
                              }
                            } finally {
                              if (context.mounted) {
                                modalSet(() => searching = false);
                              }
                            }
                          },
                    child: Text(searching ? 'Buscando…' : 'Buscar ciudad'),
                  ),
                  if (cityError.isNotEmpty) Text(cityError),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final city in results)
                          ListTile(
                            title: Text(city.name),
                            subtitle: Text(city.label),
                            onTap: () => Navigator.pop(context, city),
                          ),
                      ],
                    ),
                  ),
                  const Text(
                    'Open-Meteo recibe el nombre de la ciudad y sus coordenadas aproximadas. Las fotos permanecen en el móvil. No se solicita GPS.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    preferences = ClimatePreferences(
      automatic: true,
      manual: preferences.manual,
      city: selected,
    );
    await generate();
  }

  Future<void> saveSuggestion(OutfitSuggestion s) async {
    final outfit = Outfit(
      id: const Uuid().v4(),
      name:
          'Idea para ${MaterialLocalizations.of(context).formatMediumDate(date)}',
      occasion: occasion,
      items: s.items,
      notes: s.reasons.join('. '),
    );
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            OutfitEditor(repo: widget.repo, garments: garments, outfit: outfit),
      ),
    );
    if (mounted) {
      garments = await widget.repo.garments();
      await generate();
    }
  }

  Future<void> reviewGarments() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .65,
          child: ListView(
            children: [
              const ListTile(
                title: Text('Revisar categorías y disponibilidad'),
                subtitle: Text(
                  'Una camiseta y un pantalón deben tener categorías distintas. Cada foto del lote debe guardarse.',
                ),
              ),
              for (final g in garments)
                ListTile(
                  leading: SizedBox(
                    width: 50,
                    height: 60,
                    child: Photo(widget.repo.photoPath(g.photo)),
                  ),
                  title: Text(g.name),
                  subtitle: Text('${g.category} · ${g.status}'),
                  onTap: () async {
                    await Navigator.push(
                      sheetContext,
                      MaterialPageRoute(
                        builder: (_) =>
                            GarmentEditor(repo: widget.repo, garment: g),
                      ),
                    );
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    garments = await widget.repo.garments();
    usage = await widget.repo.usageStats();
    await generate();
  }

  Future<void> manualPlan() async {
    if (busy) return;
    final pieces = await widget.repo.garments();
    if (!mounted) return;
    if (pieces.isEmpty) {
      message(context, 'Guarda alguna prenda antes de crear el outfit.');
      return;
    }
    final id = const Uuid().v4();
    final outfit = Outfit(
      id: id,
      name: 'Outfit · ${dateKey(date)}',
      occasion: occasion,
      items: [],
    );
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            OutfitEditor(repo: widget.repo, garments: pieces, outfit: outfit),
      ),
    );
    if (saved != true || !mounted) return;
    try {
      final plans = await widget.repo.plans();
      if (!mounted) return;
      final previous = plans.where((p) => p.date == dateKey(date));
      if (previous.isNotEmpty &&
          !await confirm(
            context,
            'Cambiar outfit del día',
            'El outfit nuevo está guardado. ¿Asignarlo a ${dateKey(date)}? Sustituirá la asignación de ese día y reiniciará su marca de usado.',
            action: 'Asignar nuevo',
          )) {
        return;
      }
      await widget.repo.savePlan(DayPlan(dateKey(date), id, false));
      if (mounted) {
        message(context, 'Outfit guardado y asignado a ${dateKey(date)}.');
      }
      garments = await widget.repo.garments();
      await generate();
    } catch (e) {
      if (mounted) message(context, errorMessage(e));
    }
  }

  Future<void> proposeWeek() async {
    if (busy) return;
    final localization = MaterialLocalizations.of(context);
    setState(() => busy = true);
    final proposed = <DayPlan, Outfit>{};
    try {
      if (preferences.automatic) await updateForecast();
      final existing = await widget.repo.plans();
      final knownOutfits = await widget.repo.outfits();
      final virtualUsage = Map<String, WearStat>.from(usage);
      for (var offset = 0; offset < 7; offset++) {
        final day = calendarDayOffset(date, offset),
            key = dateKey(calendarDayOffset(date, offset));
        final previous = existing.where((p) => p.date == key);
        if (previous.isNotEmpty) {
          final o = knownOutfits.where((o) => o.id == previous.first.outfitId);
          if (o.isNotEmpty) {
            for (final i in o.first.items) {
              final old = virtualUsage[i.garmentId] ?? const WearStat();
              virtualUsage[i.garmentId] = WearStat(
                count: old.count + 1,
                lastWorn: day,
              );
            }
          }
          continue;
        }
        final candidates = RecommendationService.suggest(
          garments: garments,
          usage: virtualUsage,
          date: day,
          climate: climateFor(day),
          occasion: occasion,
          seed: seed + offset,
          anchorId: widget.anchorId,
          preferences: style,
          profile: profile,
          rainy: rainyFor(day),
          windy: windyFor(day),
          feedback: feedback,
          limit: 1,
        );
        if (candidates.isEmpty) continue;
        final s = candidates.first, id = const Uuid().v4();
        final o = Outfit(
          id: id,
          name: 'Semana · ${localization.formatMediumDate(day)}',
          occasion: occasion,
          items: s.items,
          notes: s.reasons.join('. '),
        );
        proposed[DayPlan(key, id, false)] = o;
        for (final g in s.garments) {
          final old = virtualUsage[g.id] ?? const WearStat();
          virtualUsage[g.id] = WearStat(count: old.count + 1, lastWorn: day);
        }
      }
      if (!mounted) return;
      if (proposed.isEmpty) {
        message(
          context,
          List.generate(
                7,
                (i) => dateKey(calendarDayOffset(date, i)),
              ).every((key) => existing.any((p) => p.date == key))
              ? 'Los 7 días elegidos ya tienen un outfit asignado. Cambia la fecha inicial o revisa el Calendario.'
              : RecommendationService.noSuggestionReason(
                  garments,
                  anchorId: widget.anchorId,
                ),
        );
        return;
      }
      final edited = await Navigator.push<Map<DayPlan, Outfit>>(
        context,
        MaterialPageRoute(
          builder: (_) => WeekEditor(
            repo: widget.repo,
            start: date,
            proposed: proposed,
            existing: existing,
            knownOutfits: knownOutfits,
            garments: garments,
            usage: usage,
            preferences: style,
            climateFor: climateFor,
            occasion: occasion,
            profile: profile,
            rainyFor: rainyFor,
            windyFor: windyFor,
            feedback: feedback,
          ),
        ),
      );
      if (edited != null) {
        await widget.repo.saveNewWeek(edited);
        if (mounted) {
          message(
            context,
            'Semana planificada. Los días que ya tenían outfit se han conservado.',
          );
        }
      }
    } catch (e) {
      if (mounted) message(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final day = preferences.automatic ? forecast?.forDate(date) : null;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Ideas para vestirte'),
          actions: [
            IconButton(
              tooltip: 'Restablecer preferencias',
              icon: const Icon(Icons.restart_alt),
              onPressed: () async {
                if (await confirm(
                  context,
                  'Restablecer preferencias',
                  'Se olvidarán tus valoraciones de combinaciones.',
                  action: 'Restablecer',
                )) {
                  style = StylePreferences();
                  await widget.repo.saveSetting(
                    'style_preferences',
                    style.encode(),
                  );
                  await generate();
                }
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            AbsorbPointer(
              absorbing: busy,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .48),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface.withValues(alpha: .8),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.auto_awesome_rounded,
                            size: 28,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Tu estilo, tu próxima idea',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            height: 1.12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Combinaciones hechas con tu armario. Descubre una propuesta, ajústala a tu gusto y guarda la que te encaje.',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.4),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Icon(Icons.checkroom_outlined, size: 18, color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                'Colores · clima · ocasión · uso reciente',
                                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: manualPlan,
                    icon: const Icon(Icons.add),
                    label: const Text(
                      'Elegir prendas y planificar manualmente',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final chosen = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateUtils.dateOnly(DateTime.now()),
                        lastDate: calendarDayOffset(DateTime.now(), 13),
                      );
                      if (chosen != null && mounted) {
                        date = chosen;
                        await generate();
                      }
                    },
                    icon: const Icon(Icons.event),
                    label: Text(
                      MaterialLocalizations.of(context).formatFullDate(date),
                    ),
                  ),
                  const SizedBox(height: 12),
                  choice('Estilo preferido', profile.style, outfitStyles, (v) {
                    profile.style = v;
                    generate();
                  }),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: excludePieces,
                    icon: const Icon(Icons.block),
                    label: Text(
                      'Excluir prendas este día (${profile.excludedOn(date).length})',
                    ),
                  ),
                  choice('Ocasión', occasion, occasions, (v) {
                    occasion = v;
                    generate();
                  }),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Usar el tiempo de una ciudad'),
                    value: preferences.automatic,
                    onChanged: (v) {
                      if (v && preferences.city == null) {
                        chooseCity();
                        return;
                      }
                      preferences = ClimatePreferences(
                        automatic: v,
                        manual: preferences.manual,
                        city: preferences.city,
                      );
                      generate();
                    },
                  ),
                  if (!preferences.automatic) ...[
                    SwitchListTile(
                      title: const Text('Lluvia'),
                      value: profile.rain,
                      onChanged: (v) {
                        profile.rain = v;
                        generate();
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Viento fuerte'),
                      value: profile.wind,
                      onChanged: (v) {
                        profile.wind = v;
                        generate();
                      },
                    ),
                    choice(
                      'Temperatura manual',
                      preferences.manual.label,
                      Climate.values.map((c) => c.label).toList(),
                      (v) {
                        preferences = ClimatePreferences(
                          automatic: false,
                          manual: Climate.values.firstWhere(
                            (c) => c.label == v,
                          ),
                          city: preferences.city,
                        );
                        generate();
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Frío: menos de 15 °C · Templado: 15–24 °C · Calor: 25 °C o más',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                  if (preferences.automatic) ...[
                    OutlinedButton.icon(
                      onPressed: chooseCity,
                      icon: const Icon(Icons.location_city),
                      label: Text(preferences.city?.name ?? 'Elegir ciudad'),
                    ),
                    if (day != null)
                      Text(
                        '${day.min.round()}–${day.max.round()} °C · ${day.climate.label}\nLluvia: ${day.rainProbability?.round().toString() ?? 'sin dato'} % · Viento: ${day.windSpeed?.round().toString() ?? 'sin dato'} km/h',
                      ),
                    const Text(
                      'Previsión: Open-Meteo. Solo se consulta el tiempo; las fotos no se envían.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    '${garments.length} prendas guardadas · ${garments.where((g) => g.available).length} disponibles',
                  ),
                  TextButton.icon(
                    onPressed: reviewGarments,
                    icon: const Icon(Icons.checkroom),
                    label: const Text('Revisar categorías y disponibilidad'),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () {
                          seed++;
                          generate();
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Otras propuestas'),
                      ),
                      OutlinedButton.icon(
                        onPressed: proposeWeek,
                        icon: const Icon(Icons.calendar_month),
                        label: const Text('Planificar 7 días'),
                      ),
                    ],
                  ),
                  if (error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (!busy && suggestions.isEmpty && error.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        RecommendationService.noSuggestionReason(
                          garments,
                          anchorId: widget.anchorId,
                          profile: profile,
                          date: date,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  for (final s in suggestions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .65),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              OutfitBoard(
                                repo: widget.repo,
                                garments: s.garments,
                                items: s.items,
                              ),
                              const SizedBox(height: 12),
                              CategoryOutfitView(
                                repo: widget.repo,
                                garments: s.garments,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                s.garments.map((g) => g.name).join(' + '),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      final result =
                                          await Navigator.push<
                                            OutfitSuggestion
                                          >(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => OutfitDraftScreen(
                                                repo: widget.repo,
                                                garments: garments,
                                                usage: usage,
                                                preferences: style,
                                                suggestion: s,
                                                date: date,
                                                climate: climateFor(date),
                                                occasion: occasion,
                                                profile: profile,
                                                rainy: rainyFor(date),
                                                windy: windyFor(date),
                                                feedback: feedback,
                                                initiallyLocked: {
                                                  if (widget.anchorId != null)
                                                    widget.anchorId!,
                                                },
                                              ),
                                            ),
                                          );
                                      if (result != null && mounted) {
                                        setState(
                                          () =>
                                              suggestions[suggestions.indexOf(
                                                    s,
                                                  )] =
                                                  result,
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.swap_horiz),
                                    label: const Text(
                                      'Ajustar / fijar prendas',
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => rate(s, true),
                                    icon: const Icon(Icons.thumb_up_outlined),
                                    label: const Text('Me gusta'),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => rate(s, false),
                                    icon: const Icon(Icons.thumb_down_outlined),
                                    label: const Text('No me pondría esto'),
                                  ),
                                ],
                              ),
                              for (final reason in s.reasons)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text('• $reason'),
                                ),
                              const SizedBox(height: 8),
                              if (dateKey(date) == dateKey(DateTime.now()))
                                OutlinedButton.icon(
                                  onPressed: () => markUsed(s),
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: const Text('Lo he usado hoy'),
                                ),
                              FilledButton(
                                onPressed: () => saveSuggestion(s),
                                child: const Text('Revisar y guardar outfit'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (busy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x44ffffff),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
