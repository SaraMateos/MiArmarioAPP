import 'advanced_data.dart';

import 'package:flutter/material.dart';

import 'models.dart';
import 'repository.dart';
import 'recommendation_service.dart';
import 'wardrobe_tools.dart';
import 'ui_common.dart';
import 'category_outfit_view.dart';

Future<Garment?> chooseReplacement(
  BuildContext context, {
  required WardrobeRepository repo,
  required Garment piece,
  required List<Garment> all,
  required List<Garment> current,
  required Map<String, WearStat> usage,
  required StylePreferences preferences,
  String occasion = 'Diario',
  List<List<String>> linkedSets = const [],
}) async {
  var reason = 'Otra opción';
  List<Garment> alternatives() {
    final candidates = all.where((g) {
      if (!g.available ||
          roleOf(g) != roleOf(piece) ||
          layerOf(g) != layerOf(piece) ||
          current.any((c) => c.id == g.id)) {
        return false;
      }
      final next = current.map((c) => c.id == piece.id ? g : c).toList();
      if (!RecommendationService.validAutomaticCombination(next, occasion)) {
        return false;
      }
      if (linkedSets.any(
        (group) =>
            group.any((id) => next.any((c) => c.id == id)) &&
            !group.every((id) => next.any((c) => c.id == id)),
      )) {
        return false;
      }
      if (reason == 'Tengo frío' && g.warmth <= piece.warmth) return false;
      if (reason == 'Otro color' &&
          g.colorTags.toSet().length == piece.colorTags.toSet().length &&
          g.colorTags.every(piece.colorTags.contains)) {
        return false;
      }
      if (reason == 'Menos formal' &&
          (['Americana', 'Zapatos de vestir'].contains(g.subtype) ||
              g.details['style'] == 'Elegante' ||
              (g.occasionTags.length == 1 &&
                  g.occasionTags.contains('Formal')))) {
        return false;
      }
      return true;
    }).toList();
    double score(Garment g) =>
        preferences.score(g) -
        (usage[g.id]?.count ?? 0) * 2 +
        current
                .where(
                  (c) =>
                      c.id != piece.id &&
                      RecommendationService.compatibleColors(
                        c.colorTags,
                        g.colorTags,
                      ),
                )
                .length *
            4;
    candidates.sort((a, b) => score(b).compareTo(score(a)));
    return candidates;
  }

  return showModalBottomSheet<Garment>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, update) {
        final candidates = alternatives();
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(c).height * .75,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Sustituir ${piece.name}',
                    style: Theme.of(c).textTheme.titleLarge,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: choice('Motivo', reason, [
                    'Otra opción',
                    'Tengo frío',
                    'Menos formal',
                    'Otro color',
                  ], (v) => update(() => reason = v)),
                ),
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Se conservan las demás prendas, las capas y los conjuntos vinculados.',
                  ),
                ),
                if (candidates.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No hay alternativas para este motivo. Prueba «Otra opción», revisa la disponibilidad o las exclusiones.',
                    ),
                  ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final g in candidates)
                        ListTile(
                          leading: SizedBox.square(
                            dimension: 64,
                            child: Photo(repo.photoPath(g.photo)),
                          ),
                          title: Text(g.name),
                          subtitle: Text(
                            '${g.color} · ${usage[g.id]?.count ?? 0} usos',
                          ),
                          onTap: () => Navigator.pop(c, g),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class OutfitDraftScreen extends StatefulWidget {
  final WardrobeRepository repo;
  final List<Garment> garments;
  final Map<String, WearStat> usage;
  final StylePreferences preferences;
  final OutfitSuggestion suggestion;
  final DateTime date;
  final Climate climate;
  final String occasion;
  final RecommendationProfile? profile;
  final bool rainy, windy;
  final List<Map<String, dynamic>> feedback;
  final Set<String> initiallyLocked;
  const OutfitDraftScreen({
    super.key,
    required this.repo,
    required this.garments,
    required this.usage,
    required this.preferences,
    required this.suggestion,
    required this.date,
    required this.climate,
    required this.occasion,
    this.initiallyLocked = const {},
    this.profile,
    this.rainy = false,
    this.windy = false,
    this.feedback = const [],
  });
  @override
  State<OutfitDraftScreen> createState() => _OutfitDraftScreenState();
}

class _OutfitDraftScreenState extends State<OutfitDraftScreen> {
  late List<Garment> pieces;
  late Set<String> locked;
  int seed = 0;
  @override
  void initState() {
    super.initState();
    pieces = [...widget.suggestion.garments];
    locked = {...widget.initiallyLocked};
  }

  void another() {
    final list = RecommendationService.suggest(
      garments: widget.garments,
      usage: widget.usage,
      date: widget.date,
      climate: widget.climate,
      occasion: widget.occasion,
      requiredIds: locked,
      preferences: widget.preferences,
      profile: widget.profile,
      rainy: widget.rainy,
      windy: widget.windy,
      feedback: widget.feedback,
      seed: ++seed,
      limit: 30,
    );
    final current = StylePreferences.signature(pieces);
    final next = list.where((s) => s.signature != current);
    if (next.isEmpty) {
      message(
        context,
        'No hay otra combinación que conserve las prendas fijadas.',
      );
      return;
    }
    setState(() => pieces = [...next.first.garments]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ajustar outfit')),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: () => Navigator.pop(
            context,
            OutfitSuggestion(pieces, 0, [
              'Combinación ajustada por ti; revisa el abrigo para la temperatura elegida',
            ]),
          ),
          child: const Text('Usar esta combinación'),
        ),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        CategoryOutfitView(
          repo: widget.repo,
          garments: pieces,
          compactImages: true,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: .45),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pulsa el candado para conservar una prenda. Usa las flechas para sustituir solo una; las demás se mantienen.',
                ),
              ),
            ],
          ),
        ),
        for (final g in pieces)
          Card(
            color: locked.contains(g.id)
                ? Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: .3)
                : null,
            child: ListTile(
              leading: SizedBox(
                width: 50,
                height: 60,
                child: Photo(widget.repo.photoPath(g.photo)),
              ),
              title: Text(g.name),
              subtitle: Text(
                '${g.category} · ${g.color}${locked.contains(g.id) ? ' · Fijada' : ''}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: locked.contains(g.id)
                        ? 'Desfijar prenda'
                        : 'Fijar prenda',
                    icon: Icon(
                      locked.contains(g.id) ? Icons.lock : Icons.lock_open,
                    ),
                    onPressed: widget.initiallyLocked.contains(g.id)
                        ? null
                        : () => setState(() {
                            if (!locked.add(g.id)) locked.remove(g.id);
                          }),
                  ),
                  IconButton(
                    tooltip: 'Cambiar prenda',
                    icon: const Icon(Icons.swap_horiz),
                    onPressed: locked.contains(g.id)
                        ? null
                        : () async {
                            final chosen = await chooseReplacement(
                              context,
                              repo: widget.repo,
                              piece: g,
                              all: widget.garments
                                  .where(
                                    (candidate) =>
                                        !(widget.profile
                                                ?.excludedOn(widget.date)
                                                .contains(candidate.id) ??
                                            false),
                                  )
                                  .toList(),
                              current: pieces,
                              usage: widget.usage,
                              preferences: widget.preferences,
                              occasion: widget.occasion,
                              linkedSets:
                                  widget.profile?.linkedSets ?? const [],
                            );
                            if (chosen != null && context.mounted) {
                              final next = pieces
                                  .map((p) => p.id == g.id ? chosen : p)
                                  .toList();
                              final validLinks =
                                  !(widget.profile?.linkedSets ??
                                          <List<String>>[])
                                      .any(
                                        (group) =>
                                            group.any(
                                              (id) =>
                                                  next.any((p) => p.id == id),
                                            ) &&
                                            !group.every(
                                              (id) =>
                                                  next.any((p) => p.id == id),
                                            ),
                                      );
                              if (!RecommendationService.validAutomaticCombination(
                                    next,
                                    widget.occasion,
                                  ) ||
                                  !validLinks) {
                                message(
                                  context,
                                  'Esta sustitución rompe las capas, la ocasión o un conjunto vinculado. Prueba otra propuesta.',
                                );
                                return;
                              }
                              setState(
                                () => pieces[pieces.indexOf(g)] = chosen,
                              );
                            }
                          },
                  ),
                ],
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: another,
          icon: const Icon(Icons.refresh),
          label: const Text('Otra combinación conservando las fijadas'),
        ),
      ],
    ),
  );
}
