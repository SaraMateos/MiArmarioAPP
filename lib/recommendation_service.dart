import 'advanced_data.dart';

import 'dart:math';

import 'models.dart';
import 'wardrobe_tools.dart';

enum Climate { cold, mild, hot }

extension ClimateLabel on Climate {
  String get label => switch (this) {
    Climate.cold => 'Frío',
    Climate.mild => 'Templado',
    Climate.hot => 'Calor',
  };
  static Climate fromTemperature(double t) => t < 15
      ? Climate.cold
      : t >= 25
      ? Climate.hot
      : Climate.mild;
}

class OutfitSuggestion {
  final List<Garment> garments;
  final double score;
  final List<String> reasons;
  const OutfitSuggestion(this.garments, this.score, this.reasons);
  String get signature =>
      (garments.map((g) => g.id).toList()..sort()).join('|');
  List<OutfitItem> get items => [
    for (final g in orderedGarments(garments))
      OutfitItem(
        garmentId: g.id,
        x: roleOf(g) == 'Abrigos'
            ? 1
            : roleOf(g) == 'Accesorios'
            ? 0
            : .5,
        y: switch (roleOf(g)) {
          'Parte inferior' => .55,
          'Calzado' => 1,
          'Accesorios' => .85,
          'Abrigos' => .12,
          _ => .02,
        },
        scale: switch (roleOf(g)) {
          'Vestidos' => 1.9,
          'Parte inferior' => 1.45,
          'Calzado' => .9,
          'Accesorios' => .7,
          _ => 1.35,
        },
      ),
  ];
}

class RecommendationService {
  static List<OutfitSuggestion> suggest({
    required List<Garment> garments,
    required Map<String, WearStat> usage,
    required DateTime date,
    required Climate climate,
    String occasion = 'Diario',
    String? anchorId,
    int seed = 0,
    int limit = 6,
    Set<String> requiredIds = const {},
    StylePreferences? preferences,
    RecommendationProfile? profile,
    bool rainy = false,
    bool windy = false,
    List<Map<String, dynamic>> feedback = const [],
  }) {
    final excluded = profile?.excludedOn(date) ?? <String>{};
    garments = garments
        .where(
          (g) =>
              g.available &&
              !excluded.contains(g.id) &&
              g.details['needs_review'] != true &&
              g.details['type_review'] != true,
        )
        .toList();
    final required = {...requiredIds, ?anchorId};
    for (final group in profile?.linkedSets ?? <List<String>>[]) {
      if (group.any(required.contains)) required.addAll(group);
    }
    if (!required.every((id) => garments.any((g) => g.id == id)) ||
        garments.isEmpty) {
      return [];
    }
    Garment? anchor;
    for (final g in garments) {
      if (g.id == anchorId) anchor = g;
    }
    double novelty(Garment g) {
      final u = usage[g.id] ?? const WearStat();
      final days = u.lastWorn == null
          ? 365
          : calendarDayDifference(date, u.lastWorn!);
      return (preferences?.score(g) ?? 0) +
          14 / (1 + u.count) +
          min(10, max(0, days)).toDouble() -
          (days >= 0 && days < 4 ? 18 : 0);
    }

    final random = Random(
      date.year * 10000 + date.month * 100 + date.day + seed * 7919,
    );
    final jitter = {for (final g in garments) g.id: random.nextDouble() * 3};
    List<Garment> pool(String category) {
      final p =
          garments
              .where(
                (g) => (category == 'Parte superior'
                    ? roleOf(g) == category && layerOf(g) == 'Base'
                    : category == 'Intermedia'
                    ? ['Parte superior', 'Abrigos'].contains(roleOf(g)) &&
                          layerOf(g) == 'Intermedia'
                    : category == 'Abrigos'
                    ? ['Parte superior', 'Abrigos'].contains(roleOf(g)) &&
                          layerOf(g) == 'Exterior'
                    : roleOf(g) == category),
              )
              .toList()
            ..sort(
              (a, b) => (novelty(b) + jitter[b.id]!).compareTo(
                novelty(a) + jitter[a.id]!,
              ),
            );
      final selected = p.take(8).toList();
      if (anchor != null &&
          roleOf(anchor) == category &&
          !selected.any((g) => g.id == anchor!.id)) {
        selected.add(anchor);
      }
      for (final g in p.where((g) => required.contains(g.id))) {
        if (!selected.any((s) => s.id == g.id)) selected.add(g);
      }
      return selected;
    }

    final tops = pool('Parte superior'),
        bottoms = pool('Parte inferior'),
        dresses = pool('Vestidos');
    final shoes = pool('Calzado'),
        coats = pool('Abrigos'),
        accessories = pool('Accesorios'),
        middles = pool('Intermedia');
    final bases = <List<Garment>>[
      for (final top in tops)
        for (final bottom in bottoms) [top, bottom],
      for (final dress in dresses) [dress],
    ];
    final candidates = <OutfitSuggestion>[];
    for (final base in bases) {
      final shoeOptions = shoes.isEmpty
          ? <Garment?>[null]
          : shoes.cast<Garment?>();
      final coatOptions =
          (climate == Climate.cold || rainy || windy) && coats.isNotEmpty
          ? coats.cast<Garment?>()
          : coats.any((g) => required.contains(g.id))
          ? <Garment?>[coats.firstWhere((g) => required.contains(g.id))]
          : <Garment?>[
              null,
              ...coats.where(
                (g) => (profile?.linkedSets ?? <List<String>>[]).any(
                  (group) => group.contains(g.id),
                ),
              ),
            ];
      for (final shoe in shoeOptions) {
        for (final coat in coatOptions) {
          final middleOptions = middles.any((g) => required.contains(g.id))
              ? <Garment?>[...middles.where((g) => required.contains(g.id))]
              : climate == Climate.hot
              ? <Garment?>[null]
              : <Garment?>[null, ...middles];
          for (final middle in middleOptions) {
            final accessoryCandidates = accessories
                .where(
                  (g) =>
                      g.occasionTags.contains(occasion) &&
                      validAutomaticCombination([
                        ...base,
                        ?coat,
                        ?shoe,
                        g,
                      ], occasion),
                )
                .toList();
            final requiredAccessories = accessories
                .where((g) => required.contains(g.id))
                .toList();
            final optionalAccessory = requiredAccessories.isEmpty &&
                    accessoryCandidates.isNotEmpty
                ? accessoryCandidates.first
                : null;
            final set = [
              ...base,
              ?middle,
              ?coat,
              ?shoe,
              ...requiredAccessories,
              ?optionalAccessory,
            ];
            if ((profile?.linkedSets ?? <List<String>>[]).any(
              (group) =>
                  group.any((id) => set.any((g) => g.id == id)) &&
                  !group.every((id) => set.any((g) => g.id == id)),
            )) {
              continue;
            }
            if (!required.every((id) => set.any((g) => g.id == id))) continue;
            if (preferences?.outfits[StylePreferences.signature(set)] == -1) {
              continue;
            }
            if (set.map((g) => g.id).toSet().length != set.length) continue;
            final clothes = set
                .where(
                  (g) => [
                    'Parte superior',
                    'Parte inferior',
                    'Vestidos',
                    'Abrigos',
                  ].contains(roleOf(g)),
                )
                .toList();
            final average =
                clothes.fold<int>(0, (n, g) => n + g.warmth) / clothes.length;
            final baseClothes = clothes
                .where(
                  (g) =>
                      !['Parte superior', 'Abrigos'].contains(roleOf(g)) ||
                      layerOf(g) == 'Base',
                )
                .toList();
            final baseWarmth =
                baseClothes.fold<int>(0, (n, g) => n + g.warmth) /
                baseClothes.length;
            final effectiveWarmth = (middle != null || coat != null)
                ? min(
                    3.0,
                    baseWarmth +
                        (middle == null ? 0 : .3 + middle.warmth * .2) +
                        (coat == null ? 0 : .25 + (coat.warmth - 1) * .65),
                  )
                : average;
            final target = climate == Climate.cold
                ? 3.0
                : climate == Climate.hot
                ? 1.0
                : 2.0;
            final temperatureScore =
                20 - max(0, (effectiveWarmth - target).abs() * 13);
            var compatiblePairs = 0;
            var pairCount = 0;
            for (var a = 0; a < set.length; a++) {
              for (var b = a + 1; b < set.length; b++) {
                pairCount++;
                if (compatibleColors(set[a].colorTags, set[b].colorTags)) {
                  compatiblePairs++;
                }
              }
            }
            final colorScore = pairCount == 0
                ? 15.0
                : 30.0 * compatiblePairs / pairCount;
            final variety =
                set.fold<double>(0, (n, g) => n + novelty(g)) / set.length;
            final matchingSeasons = climate == Climate.cold
                ? {'Invierno', 'Otoño'}
                : climate == Climate.hot
                ? {'Verano', 'Primavera'}
                : {'Primavera', 'Otoño'};
            final seasonScore =
                6 *
                clothes
                    .where(
                      (g) =>
                          g.seasonTags.contains('Todo el año') ||
                          g.seasonTags.any(matchingSeasons.contains),
                    )
                    .length /
                clothes.length;
            final occasionScore =
                12 *
                set.where((g) => g.occasionTags.contains(occasion)).length /
                set.length;
            final recent = set.where((g) {
              final last = usage[g.id]?.lastWorn;
              return last != null &&
                  calendarDayDifference(date, last) >= 0 &&
                  calendarDayDifference(date, last) < 4;
            }).toList();
            final least =
                (set.toList()..sort(
                      (a, b) => (usage[a.id]?.count ?? 0).compareTo(
                        usage[b.id]?.count ?? 0,
                      ),
                    ))
                    .first;
            var extraScore = 0.0;
            final desiredStyle = profile?.style ?? 'Sin preferencia';
            if (desiredStyle != 'Sin preferencia') {
              for (final g in set) {
                if (desiredStyle == 'Casual' &&
                    g.occasionTags.contains('Diario')) {
                  extraScore += 3;
                }
                if (g.details['style'] == desiredStyle) extraScore += 4;
                if (desiredStyle == 'Deportivo' &&
                    g.occasionTags.contains('Deporte')) {
                  extraScore += 3;
                }
                if (desiredStyle == 'Elegante' &&
                    g.occasionTags.any(['Formal', 'Trabajo'].contains)) {
                  extraScore += 3;
                }
              }
              if (desiredStyle == 'Minimalista') {
                extraScore += set.expand((g) => g.colorTags).toSet().length <= 3
                    ? 10
                    : -6;
              }
            }
            if (rainy) {
              extraScore +=
                  (shoe?.details['rain'] == true ? 14 : -8) +
                  (coat?.details['rain'] == true ? 14 : -8);
            }
            if (windy) extraScore += coat?.details['wind'] == true ? 18 : -10;
            var feedbackScore = 0.0;
            for (final f in feedback) {
              final previous = (f['items'] as List?)?.cast<String>() ?? [];
              final overlap =
                  set.where((g) => previous.contains(g.id)).length / set.length;
              if (overlap < .6) continue;
              feedbackScore += switch (f['rating']) {
                'Cómodo' => 4.0 * overlap,
                'No me convenció' => -8.0 * overlap,
                'Pasé frío' => (effectiveWarmth - 2) * 5 * overlap,
                'Demasiado abrigado' => (2 - effectiveWarmth) * 5 * overlap,
                _ => 0.0,
              };
            }
            extraScore += feedbackScore.clamp(-12, 12);
            final reasons = <String>[
              if (desiredStyle != 'Sin preferencia')
                'Orientado a estilo ${desiredStyle.toLowerCase()}',
              if (middle != null)
                'Base + capa intermedia${coat != null ? ' + exterior' : ''}',
              if (rainy)
                shoe?.details['rain'] == true && coat?.details['rain'] == true
                    ? 'Calzado y exterior con protección de lluvia indicada'
                    : 'Lluvia: falta confirmar protección del calzado o exterior',
              if (windy)
                coat?.details['wind'] == true
                    ? 'Exterior con protección del viento indicada'
                    : 'Viento: revisa la protección de la capa exterior',
              if (feedback.isNotEmpty)
                'Se tienen en cuenta tus valoraciones después del uso',
              colorScore >= 24
                  ? 'Colores compatibles'
                  : 'Una combinación de colores diferente',
              (effectiveWarmth - target).abs() <= .7
                  ? 'Adecuado para ${climate.label.toLowerCase()}'
                  : 'Revisa el abrigo para esta temperatura',
              'Recupera «${least.name}»: ${usage[least.id]?.count ?? 0} usos registrados',
              recent.isEmpty
                  ? 'Sin prendas usadas en los últimos 3 días'
                  : 'Incluye ${recent.length} prendas usadas recientemente',
              if (shoe == null) 'Falta añadir calzado a tu armario',
              if (climate == Climate.cold &&
                  coat == null &&
                  effectiveWarmth < 2.5)
                'Puede hacer falta una capa de abrigo',
            ];
            if (!validAutomaticCombination(set, occasion)) continue;
            candidates.add(
              OutfitSuggestion(
                orderedGarments(set),
                (preferences?.outfits[StylePreferences.signature(set)] == 1
                        ? 8
                        : 0) +
                    extraScore +
                    colorScore +
                    temperatureScore +
                    variety +
                    occasionScore +
                    seasonScore,
                reasons,
              ),
            );
          }
        }
      }
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));
    final result = <OutfitSuggestion>[], signatures = <String>{};
    // Diversify using Jaccard similarity: shared pieces divided by the
    // union of both outfits. This avoids treating a short outfit and a long
    // outfit as nearly identical just because most pieces of the shorter one
    // are shared.
    for (final s in candidates) {
      if (!signatures.add(s.signature)) continue;
      final ids = s.garments.map((g) => g.id).toSet();
      final tooSimilar = result.any((r) {
        final otherIds = r.garments.map((g) => g.id).toSet();
        final shared = otherIds.intersection(ids).length;
        final total = otherIds.union(ids).length;
        return total > 0 && shared / total > .65;
      });
      if (tooSimilar) continue;
      result.add(s);
      if (result.length >= limit) break;
    }
    if (result.length < limit) {
      for (final s in candidates) {
        if (result.any((r) => r.signature == s.signature)) continue;
        result.add(s);
        if (result.length >= limit) break;
      }
    }
    return result;
  }

  static bool validAutomaticCombination(List<Garment> pieces, String occasion) {
    final roles = pieces.map(roleOf).toList();
    if (roles.where((r) => r == 'Parte inferior').length > 1 ||
        pieces
                .where(
                  (g) =>
                      ['Parte superior', 'Abrigos'].contains(roleOf(g)) &&
                      layerOf(g) == 'Base',
                )
                .length >
            1 ||
        pieces
                .where(
                  (g) =>
                      ['Parte superior', 'Abrigos'].contains(roleOf(g)) &&
                      layerOf(g) == 'Intermedia',
                )
                .length >
            1 ||
        pieces
                .where(
                  (g) =>
                      ['Parte superior', 'Abrigos'].contains(roleOf(g)) &&
                      layerOf(g) == 'Exterior',
                )
                .length >
            1 ||
        roles.where((r) => r == 'Vestidos').length > 1 ||
        roles.where((r) => r == 'Calzado').length > 1) {
      return false;
    }
    if (roles.contains('Vestidos') &&
        (pieces.any(
              (g) => roleOf(g) == 'Parte superior' && layerOf(g) == 'Base',
            ) ||
            roles.contains('Parte inferior'))) {
      return false;
    }
    const sport = {'Camiseta deportiva', 'Pantalón deportivo', 'Leggings'};
    const formal = {'Americana', 'Zapatos de vestir'};
    bool sporty(Garment g) =>
        sport.contains(g.subtype) ||
        (g.occasionTags.length == 1 && g.occasionTags.contains('Deporte'));
    bool formalPiece(Garment g) =>
        formal.contains(g.subtype) ||
        (g.occasionTags.length == 1 && g.occasionTags.contains('Formal'));
    if (pieces.any(sporty) && pieces.any(formalPiece)) return false;
    if (occasion == 'Formal' && pieces.any(sporty)) return false;
    if (occasion == 'Deporte' && pieces.any(formalPiece)) return false;
    return true;
  }

  static String noSuggestionReason(
    List<Garment> garments, {
    String? anchorId,
    RecommendationProfile? profile,
    DateTime? date,
  }) {
    final pending = garments
        .where(
          (g) =>
              g.details['needs_review'] == true ||
              g.details['type_review'] == true,
        )
        .length;
    if (pending > 0) {
      final reviewed = garments
          .where(
            (g) =>
                g.details['needs_review'] != true &&
                g.details['type_review'] != true,
          )
          .toList();
      return '$pending fichas Por revisar. Confirma su tipo para incluirlas en propuestas. ${noSuggestionReason(reviewed, anchorId: anchorId, profile: profile, date: date)}';
    }
    final excluded = date == null
        ? <String>{}
        : profile?.excludedOn(date) ?? <String>{};
    if (excluded.isNotEmpty) {
      if (anchorId != null && excluded.contains(anchorId)) {
        return 'La prenda fijada está excluida para este día. Revisa las exclusiones.';
      }
      final remaining = garments
          .where((g) => !excluded.contains(g.id))
          .toList();
      return '${excluded.length} prendas excluidas para este día. ${noSuggestionReason(remaining, anchorId: anchorId)} Revisa también los conjuntos vinculados y el estilo seleccionado.';
    }
    final blocked = (profile?.linkedSets ?? <List<String>>[])
        .where(
          (group) => group.any(
            (id) => !garments.any((g) => g.id == id && g.available),
          ),
        )
        .length;
    if (blocked > 0) {
      return '$blocked conjuntos vinculados tienen alguna prenda no disponible. Revisa su disponibilidad o desvincúlalos. ${noSuggestionReason(garments, anchorId: anchorId)}';
    }
    if (garments.isEmpty) {
      return 'Todavía no hay prendas guardadas. Tras importar fotos, revisa cada una y pulsa Guardar prenda.';
    }
    final available = garments.where((g) => g.available).toList();
    if (available.isEmpty) {
      return 'Las ${garments.length} prendas están en lavado o guardadas. Cambia alguna a Disponible para proponer outfits.';
    }
    final tops = available.where((g) => roleOf(g) == 'Parte superior').length;
    final bottoms = available
        .where((g) => roleOf(g) == 'Parte inferior')
        .length;
    final dresses = available.where((g) => roleOf(g) == 'Vestidos').length;
    final summary =
        'Disponibles: $tops partes superiores, $bottoms partes inferiores y $dresses vestidos.';
    Garment? anchor;
    if (anchorId != null) {
      for (final g in garments) {
        if (g.id == anchorId) anchor = g;
      }
      if (anchor == null) return 'La prenda elegida ya no está en el armario.';
      if (!anchor.available) {
        return '«${anchor.name}» está ${anchor.status.toLowerCase()}. Ponla como Disponible o elige otra prenda.';
      }
      if (roleOf(anchor) == 'Parte superior' && bottoms == 0) {
        return '$summary Falta una parte inferior disponible para combinar con «${anchor.name}».';
      }
      if (roleOf(anchor) == 'Parte inferior' && tops == 0) {
        return '$summary Falta una parte superior disponible para combinar con «${anchor.name}».';
      }
    }
    if (dresses == 0 && (tops == 0 || bottoms == 0)) {
      final missing = tops == 0 && bottoms == 0
          ? 'una parte superior y una inferior, o un vestido'
          : tops == 0
          ? 'una parte superior o un vestido'
          : 'una parte inferior o un vestido';
      return '$summary Falta $missing disponible. Revisa las categorías: si falló la detección, las fotos pueden haber quedado como Parte superior.';
    }
    return '$summary No hay una combinación válida con la prenda elegida y tus valoraciones. Revisa la categoría o restablece las preferencias de Ideas.';
  }

  static bool compatibleColors(List<String> a, List<String> b) {
    const neutral = {'Negro', 'Blanco', 'Gris', 'Beige', 'Marrón'};
    const groups = [
      {'Azul', 'Verde', 'Morado'},
      {'Rojo', 'Rosa', 'Naranja'},
      {'Amarillo', 'Naranja', 'Marrón'},
      {'Azul', 'Naranja'},
      {'Verde', 'Rosa'},
      {'Morado', 'Amarillo'},
    ];
    for (final x in a) {
      for (final y in b) {
        if (x == y ||
            neutral.contains(x) ||
            neutral.contains(y) ||
            groups.any((g) => g.contains(x) && g.contains(y))) {
          return true;
        }
      }
    }
    return false;
  }
}
