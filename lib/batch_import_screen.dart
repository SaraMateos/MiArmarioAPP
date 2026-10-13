import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'garment_editor.dart';
import 'repository.dart';
import 'ui_common.dart';

class BatchImportScreen extends StatefulWidget {
  final WardrobeRepository repo;
  final List<XFile> files;
  const BatchImportScreen({super.key, required this.repo, required this.files});
  @override
  State<BatchImportScreen> createState() => _BatchImportScreenState();
}

class _BatchImportScreenState extends State<BatchImportScreen> {
  final Set<int> saved = {}, skipped = {};
  bool opening = false;
  Future<void> review(int i) async {
    if (opening || saved.contains(i)) return;
    setState(() => opening = true);
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => GarmentEditor(
          repo: widget.repo,
          recoveredPhoto: widget.files[i].path,
          batchMode: true,
        ),
      ),
    );
    if (mounted) {
      setState(() {
        if (result == true) {
          saved.add(i);
          skipped.remove(i);
        }
        opening = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Añadir varias prendas')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          '${saved.length} guardadas de ${widget.files.length}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Cada foto será una prenda independiente. Revisa los datos sugeridos y guarda las que quieras añadir. Las ya guardadas se conservan al salir.',
        ),
        const SizedBox(height: 20),
        for (var i = 0; i < widget.files.length; i++)
          Card(
            child: ListTile(
              leading: SizedBox.square(
                dimension: 60,
                child: Photo(widget.files[i].path),
              ),
              title: Text('Prenda ${i + 1}'),
              subtitle: Text(
                saved.contains(i)
                    ? 'Guardada'
                    : skipped.contains(i)
                    ? 'Omitida'
                    : 'Pendiente de revisar',
              ),
              onTap: opening || saved.contains(i) ? null : () => review(i),
              trailing: saved.contains(i)
                  ? const Icon(Icons.check_circle_outline)
                  : PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'review') {
                          review(i);
                        } else {
                          setState(() => skipped.add(i));
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'review',
                          child: Text('Revisar y guardar'),
                        ),
                        PopupMenuItem(value: 'skip', child: Text('Omitir')),
                      ],
                    ),
            ),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: opening ? null : () => Navigator.pop(context),
          child: const Text('Finalizar importación'),
        ),
      ],
    ),
  );
}
