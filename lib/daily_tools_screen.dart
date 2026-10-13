import 'package:flutter/material.dart';

import 'models.dart';
import 'repository.dart';
import 'ui_common.dart';
import 'garment_editor.dart';

class DailyToolsScreen extends StatefulWidget {
  final WardrobeRepository repo;
  final bool laundry;
  const DailyToolsScreen({
    super.key,
    required this.repo,
    required this.laundry,
  });
  @override
  State<DailyToolsScreen> createState() => _DailyToolsScreenState();
}

class _DailyToolsScreenState extends State<DailyToolsScreen> {
  List<Garment>? garments;
  final selected = <String>{};
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final all = await widget.repo.garments();
      if (!mounted) return;
      setState(() {
        garments = all
            .where(
              (g) => widget.laundry
                  ? g.status == 'En lavado'
                  : g.status != 'Archivada' &&
                        (g.subtype.isEmpty ||
                            (g.details['needs_review'] == true ||
                                g.details['type_review'] == true)),
            )
            .toList();
        selected.retainAll(garments!.map((g) => g.id));
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = errorMessage(e));
    }
  }

  Future<void> clean() async {
    if (selected.isEmpty || busy) return;
    setState(() => busy = true);
    try {
      await widget.repo.batchUpdate(selected, {'status': 'Disponible'});
      selected.clear();
      await load();
    } catch (e) {
      if (mounted) message(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.laundry ? 'Prendas en lavado' : 'Fichas por revisar'),
    ),
    bottomNavigationBar: widget.laundry
        ? SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: busy || selected.isEmpty ? null : clean,
                icon: const Icon(Icons.check),
                label: Text('Ya están limpias (${selected.length})'),
              ),
            ),
          )
        : null,
    body: error != null
        ? EmptyView(
            icon: Icons.error_outline,
            title: 'No se pudieron cargar las prendas',
            subtitle: error!,
            onAction: load,
            action: 'Reintentar',
          )
        : garments == null
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                widget.laundry
                    ? 'Selecciona las prendas limpias para volver a ponerlas como disponibles.'
                    : 'Confirma el tipo de estas prendas para mejorar las propuestas.',
              ),
              if (garments!.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No hay prendas pendientes.'),
                ),
              if (widget.laundry && garments!.isNotEmpty)
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          if (selected.length == garments!.length) {
                            selected.clear();
                          } else {
                            selected.addAll(garments!.map((g) => g.id));
                          }
                        }),
                  child: const Text('Seleccionar / desmarcar todas'),
                ),
              for (final g in garments!)
                widget.laundry
                    ? CheckboxListTile(
                        secondary: SizedBox.square(
                          dimension: 64,
                          child: Photo(widget.repo.photoPath(g.photo)),
                        ),
                        title: Text(g.name),
                        value: selected.contains(g.id),
                        onChanged: busy
                            ? null
                            : (v) => setState(() {
                                if (v == true) {
                                  selected.add(g.id);
                                } else {
                                  selected.remove(g.id);
                                }
                              }),
                      )
                    : ListTile(
                        leading: SizedBox.square(
                          dimension: 64,
                          child: Photo(widget.repo.photoPath(g.photo)),
                        ),
                        title: Text(g.name),
                        subtitle: Text(
                          g.subtype.isEmpty
                              ? 'Tipo sin especificar'
                              : '${g.subtype} · Por revisar',
                        ),
                        trailing: const Icon(Icons.chevron_right),
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
            ],
          ),
  );
}
