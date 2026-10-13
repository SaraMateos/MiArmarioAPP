import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import 'models.dart';
import 'repository.dart';
import 'backup_service.dart';
import 'ui_common.dart';

class BackupScreen extends StatefulWidget {
  final WardrobeRepository repo;
  const BackupScreen({super.key, required this.repo});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  WardrobeRepository get repo => widget.repo;
  bool busy = false, loading = true;
  String? error;
  List<Garment> garments = [];
  List<Outfit> outfits = [];
  List<DayPlan> plans = [];
  Map<String, dynamic> reminder = {};
  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final g = await repo.garments(),
          o = await repo.outfits(),
          d = await repo.plans();
      final r = Map<String, dynamic>.from(
        jsonDecode(await repo.setting('backup_reminder') ?? '{}') as Map,
      );
      if (mounted) {
        setState(() {
          garments = g;
          outfits = o;
          plans = d;
          reminder = r;
          loading = false;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = errorMessage(e);
          loading = false;
        });
      }
    }
  }

  Future<void> action(Future<void> Function() operation) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await operation();
      await reload();
    } catch (e) {
      if (mounted) message(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> exportBackup() => action(() async {
    final bytes = await BackupService(repo).export();
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Guardar copia del armario',
      fileName: 'MiArmario_${DateTime.now().millisecondsSinceEpoch}.zip',
      type: FileType.custom,
      allowedExtensions: ['zip'],
      bytes: bytes,
    );
    if (path != null) {
      reminder = {
        ...reminder,
        'last_export': dateKey(DateTime.now()),
        'snooze_until': '',
      };
      await repo.saveSetting('backup_reminder', jsonEncode(reminder));
    }
    if (path != null && mounted) {
      message(
        context,
        'Copia guardada. Consérvala fuera del móvil para poder recuperarla.',
      );
    }
  });
  Future<void> importBackup() async {
    if (!await confirm(
      context,
      'Restaurar armario',
      'La copia sustituirá las prendas, outfits y calendario actuales. Exporta primero una copia si quieres conservarlos.',
      action: 'Elegir copia',
    )) {
      return;
    }
    await action(() async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        withData: false,
      );
      if (result == null) {
        return;
      }
      final path = result.files.single.path;
      if (path == null) {
        throw const FormatException(
          'No se ha podido leer el archivo seleccionado.',
        );
      }
      final file = File(path);
      if (await file.length() > BackupService.maxZipBytes) {
        throw const FormatException('La copia supera 250 MB.');
      }
      await BackupService(repo).restore(await file.readAsBytes());
      if (mounted) {
        message(context, 'Armario restaurado correctamente.');
      }
    });
  }

  Future<void> saveReminder(Map<String, dynamic> value) async {
    await action(() async {
      await repo.saveSetting('backup_reminder', jsonEncode(value));
    });
  }

  Widget backups() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Siempre contigo',
        style: Theme.of(context).textTheme.headlineMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      const Text(
        'Tu armario funciona sin cuenta, sin servidor y sin conexión.',
      ),
      const SizedBox(height: 24),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.inventory_2_outlined, size: 36),
              const SizedBox(height: 16),
              Text('${garments.length} prendas · ${outfits.length} outfits'),
              const SizedBox(height: 8),
              Text(
                '${plans.where((p) => p.worn).length} días con outfits utilizados',
              ),
              const SizedBox(height: 8),
              const Text('Mi Armario · 1.7.1 reconstruida'),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      const Text(
        'Protege tus fotos',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      const Text(
        'Al desinstalar la aplicación o borrar sus datos se pierde el armario local. Guarda una copia ZIP en tu ordenador o en un lugar seguro. Incluye prendas, fotos, outfits y calendario.',
      ),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: busy ? null : exportBackup,
        icon: const Icon(Icons.upload_file),
        label: const Text('Exportar copia de seguridad'),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: busy ? null : importBackup,
        icon: const Icon(Icons.restore),
        label: const Text('Restaurar desde una copia'),
      ),
      const SizedBox(height: 20),
      SwitchListTile(
        title: const Text('Recordar copia semanal al abrir la app'),
        value: reminder['enabled'] != false,
        onChanged: (v) => saveReminder({...reminder, 'enabled': v}),
      ),
      Text(
        reminder['last_export'] == null
            ? 'Aún no se ha exportado una copia desde esta instalación.'
            : 'Última exportación: ${reminder['last_export']}',
      ),
      const Text(
        'Las copias no están cifradas. Solo compártelas con quien quieras que vea tus prendas y fotos. Límite: 250 MB de ZIP y 500 MB de contenido.',
      ),
      const SizedBox(height: 28),
      const Text(
        'Sobre esta versión',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      const Text(
        'Las fotos se analizan en el móvil. Puedes revisar el recorte y los datos sugeridos. Las recomendaciones combinan colores, temperatura y uso registrado. El tiempo por ciudad usa Internet; las fotos no se envían.',
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Copias de seguridad')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? EmptyView(
              icon: Icons.error_outline,
              title: 'No se pudo cargar la información',
              subtitle: error!,
              onAction: reload,
              action: 'Reintentar',
            )
          : AbsorbPointer(absorbing: busy, child: backups()),
      bottomNavigationBar: busy
          ? const SafeArea(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('Procesando copia…'),
                  ],
                ),
              ),
            )
          : null,
    ),
  );
}
