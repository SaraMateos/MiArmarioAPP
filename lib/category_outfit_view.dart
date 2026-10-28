import 'package:flutter/material.dart';

import 'models.dart';
import 'repository.dart';
import 'ui_common.dart';

class CategoryOutfitView extends StatelessWidget {
  final WardrobeRepository repo;
  final List<Garment> garments;
  final Map<String, int> repetitions;
  final bool compact;
  final bool compactImages;
  final bool showNames;
  const CategoryOutfitView({
    super.key,
    required this.repo,
    required this.garments,
    this.repetitions = const {},
    this.compact = false,
    this.compactImages = false,
    this.showNames = true,
  });
  String _presentationRole(Garment garment) {
    final role = roleOf(garment);
    if (role == 'Parte superior') {
      return 'Prenda superior · ${layerOf(garment)}';
    }
    if (role == 'Abrigos') return 'Abrigo · ${layerOf(garment)}';
    if (role == 'Parte inferior') return 'Prenda inferior';
    return role;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final columns = compact || bounds.maxWidth >= 600 ? 3 : 2;
      final width = (bounds.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final g in orderedGarments(garments))
            SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _presentationRole(g),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ColoredBox(
                      color: const Color(0xffeeeae2),
                      child: SizedBox(
                        height: compact || compactImages ? 88 : 130,
                        width: width,
                        child: Photo(
                          repo.photoPath(g.photo),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  if (showNames) ...[
                    const SizedBox(height: 5),
                    Text(
                      g.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      g.subtype.isEmpty ? 'Tipo sin especificar' : g.subtype,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if ((repetitions[g.id] ?? 0) > 1)
                    Text(
                      '${repetitions[g.id]} veces esta semana',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  if (!g.available)
                    Text(
                      g.status,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
        ],
      );
    },
  );
}
