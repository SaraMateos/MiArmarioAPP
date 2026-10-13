import 'advanced_data.dart';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'repository.dart';
import 'recommendation_service.dart';
import 'wardrobe_tools.dart';
import 'outfit_draft_screen.dart';
import 'ui_common.dart';
import 'category_outfit_view.dart';

class WeekEditor extends StatefulWidget {
  final WardrobeRepository repo;
  final DateTime start;
  final Map<DayPlan, Outfit> proposed;
  final List<DayPlan> existing;
  final List<Outfit> knownOutfits;
  final List<Garment> garments;
  final Map<String, WearStat> usage;
  final StylePreferences preferences;
  final Climate Function(DateTime) climateFor;
  final String occasion;
  final RecommendationProfile? profile;
  final bool Function(DateTime)? rainyFor, windyFor;
  final List<Map<String, dynamic>> feedback;
  const WeekEditor({
    super.key,
    required this.repo,
    required this.start,
    required this.proposed,
    required this.existing,
    required this.knownOutfits,
    required this.garments,
    required this.usage,
    required this.preferences,
    required this.climateFor,
    required this.occasion,
    this.profile,
    this.rainyFor,
    this.windyFor,
    this.feedback = const [],
  });
  @override
  State<WeekEditor> createState() => _WeekEditorState();
}

class _WeekEditorState extends State<WeekEditor> {
  late Map<String, Outfit> drafts;
  late Map<String, Outfit> protected;
  int seed = 0;
  final dayOccasions = <String, String>{};
  @override
  void initState() {
    super.initState();
    drafts = {for (final e in widget.proposed.entries) e.key.date: e.value};
    for (var i = 0; i < 7; i++) {
      final key = dateKey(calendarDayOffset(widget.start, i));
      dayOccasions[key] = drafts[key]?.occasionTags.first ?? widget.occasion;
    }
    protected = {};
    for (final p in widget.existing) {
      if (p.date.compareTo(dateKey(widget.start)) < 0 ||
          p.date.compareTo(dateKey(calendarDayOffset(widget.start, 6))) > 0) {
        continue;
      }
      for (final o in widget.knownOutfits) {
        if (p.outfitId == o.id) protected[p.date] = o;
      }
    }
  }

  List<Garment> pieces(Outfit o) => o.items
      .map((i) => widget.garments.firstWhere((g) => g.id == i.garmentId))
      .toList();
  Outfit withPieces(Outfit old, List<Garment> garments) => Outfit(
    id: old.id,
    name: old.name,
    occasionTags: old.occasionTags,
    referencePhoto: old.referencePhoto,
    items: OutfitSuggestion(garments, 0, []).items,
    notes: 'Semana revisada manualmente',
  );
  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (var i = 0; i < 7; i++) {
      final key = dateKey(calendarDayOffset(widget.start, i)),
          o = drafts[key] ?? protected[key];
      if (o != null) {
        for (final p in o.items) {
          counts[p.garmentId] = (counts[p.garmentId] ?? 0) + 1;
        }
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Revisar semana')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: drafts.isEmpty
                ? null
                : () => Navigator.pop(context, {
                    for (final e in drafts.entries)
                      DayPlan(e.key, e.value.id, false): e.value,
                  }),
            child: Text('Guardar ${drafts.length} días nuevos'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Ajusta las prendas o intercambia días antes de guardar. Los días ya planificados se conservan. La etiqueta de repetición cuenta toda esta semana.',
          ),
          for (var i = 0; i < 7; i++)
            dayCard(calendarDayOffset(widget.start, i), counts),
        ],
      ),
    );
  }

  void regenerate(DateTime day, {bool occasionChanged = false}) {
    final key = dateKey(day), o = drafts[dateKey(day)];
    final virtual = Map<String, WearStat>.from(widget.usage);
    for (final e in {...protected, ...drafts}.entries) {
      if (e.key == key || e.key.compareTo(key) > 0) continue;
      for (final p in e.value.items) {
        final old = virtual[p.garmentId] ?? const WearStat();
        virtual[p.garmentId] = WearStat(
          count: old.count + 1,
          lastWorn: DateTime.parse(e.key),
        );
      }
    }
    final list = RecommendationService.suggest(
      garments: widget.garments,
      usage: virtual,
      date: day,
      climate: widget.climateFor(day),
      occasion: dayOccasions[key]!,
      preferences: widget.preferences,
      profile: widget.profile,
      rainy: widget.rainyFor?.call(day) ?? false,
      windy: widget.windyFor?.call(day) ?? false,
      feedback: widget.feedback,
      seed: ++seed,
    );
    final alternatives = list.where(
      (s) =>
          occasionChanged ||
          o == null ||
          s.signature != StylePreferences.signature(pieces(o)),
    );
    if (alternatives.isEmpty) {
      if (occasionChanged) setState(() => drafts.remove(key));
      message(
        context,
        'No hay propuesta para esta ocasión. Revisa las prendas o elige otra ocasión.',
      );
      return;
    }
    setState(
      () => drafts[key] = Outfit(
        id: o?.id ?? const Uuid().v4(),
        name: 'Semana · $key',
        occasion: dayOccasions[key]!,
        items: alternatives.first.items,
      ),
    );
  }

  Widget dayCard(DateTime day, Map<String, int> counts) {
    final key = dateKey(day),
        o = drafts[key] ?? protected[key],
        isProtected = protected.containsKey(key);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              MaterialLocalizations.of(context).formatFullDate(day),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'Temperatura: ${widget.climateFor(day).label}. Revisa el abrigo si intercambias días.',
            ),
            if (!isProtected)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: choice(
                  'Ocasión de este día',
                  dayOccasions[key]!,
                  occasions,
                  (v) {
                    dayOccasions[key] = v;
                    regenerate(day, occasionChanged: true);
                  },
                ),
              ),
            if (isProtected) const Text('Ya planificado · se conserva'),
            if (o == null) const Text('Sin propuesta'),
            if (o != null) ...[
              const SizedBox(height: 8),
              CategoryOutfitView(
                repo: widget.repo,
                garments: pieces(o),
                repetitions: counts,
                compact: true,
              ),
              if (!isProtected)
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.edit),
                      label: const Text('Cambiar prendas'),
                      onPressed: () async {
                        final s = await Navigator.push<OutfitSuggestion>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OutfitDraftScreen(
                              repo: widget.repo,
                              garments: widget.garments,
                              usage: widget.usage,
                              preferences: widget.preferences,
                              suggestion: OutfitSuggestion(pieces(o), 0, []),
                              date: day,
                              climate: widget.climateFor(day),
                              occasion: dayOccasions[key]!,
                              profile: widget.profile,
                              rainy: widget.rainyFor?.call(day) ?? false,
                              windy: widget.windyFor?.call(day) ?? false,
                              feedback: widget.feedback,
                            ),
                          ),
                        );
                        if (s != null && mounted) {
                          setState(
                            () => drafts[key] = withPieces(o, s.garments),
                          );
                        }
                      },
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.swap_vert),
                      label: const Text('Mover a otro día'),
                      onPressed: () async {
                        final target = await showDialog<String>(
                          context: context,
                          builder: (context) => SimpleDialog(
                            title: const Text('Intercambiar con día libre'),
                            children: [
                              for (var i = 0; i < 7; i++)
                                if (dateKey(
                                          calendarDayOffset(widget.start, i),
                                        ) !=
                                        key &&
                                    !protected.containsKey(
                                      dateKey(
                                        calendarDayOffset(widget.start, i),
                                      ),
                                    ))
                                  SimpleDialogOption(
                                    onPressed: () => Navigator.pop(
                                      context,
                                      dateKey(
                                        calendarDayOffset(widget.start, i),
                                      ),
                                    ),
                                    child: Text(
                                      MaterialLocalizations.of(context)
                                          .formatMediumDate(
                                            calendarDayOffset(widget.start, i),
                                          ),
                                    ),
                                  ),
                            ],
                          ),
                        );
                        if (target != null && mounted) {
                          setState(() {
                            final other = drafts.remove(target);
                            drafts[target] = drafts.remove(key)!;
                            if (other != null) drafts[key] = other;
                            dayOccasions[target] =
                                drafts[target]!.occasionTags.first;
                            dayOccasions[key] =
                                drafts[key]?.occasionTags.first ??
                                widget.occasion;
                          });
                        }
                      },
                    ),
                    TextButton(
                      onPressed: () => setState(() => drafts.remove(key)),
                      child: const Text('Dejar libre'),
                    ),
                  ],
                ),
            ],
            if (!isProtected)
              TextButton.icon(
                icon: const Icon(Icons.refresh),
                label: Text(o == null ? 'Proponer outfit' : 'Otra propuesta'),
                onPressed: () => regenerate(day),
              ),
          ],
        ),
      ),
    );
  }
}
