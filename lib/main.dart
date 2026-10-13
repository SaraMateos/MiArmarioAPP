import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'repository.dart';
import 'home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WardrobeApp());
}

class WardrobeApp extends StatelessWidget {
  const WardrobeApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Mi Armario',
    debugShowCheckedModeBanner: false,
    locale: const Locale('es'),
    supportedLocales: const [Locale('es')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff355c4e),
        surface: const Color(0xfffaf8f4),
      ),
      scaffoldBackgroundColor: const Color(0xfffaf8f4),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
      ),
      cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xfffaf8f4),
        centerTitle: false,
      ),
    ),
    home: const Bootstrap(),
  );
}

class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});
  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  late Future<WardrobeRepository> future;
  @override
  void initState() {
    super.initState();
    future = open();
  }

  Future<WardrobeRepository> open() async {
    final directory = await getApplicationDocumentsDirectory();
    return WardrobeRepository.open(
      Directory(p.join(directory.path, 'wardrobe')),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<WardrobeRepository>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return WardrobeHome(repo: snapshot.data!);
      }
      return Scaffold(
        body: Center(
          child: snapshot.hasError
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.storage_outlined, size: 48),
                      const SizedBox(height: 16),
                      const Text(
                        'No se ha podido abrir el armario. Comprueba el espacio libre del móvil.',
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => setState(() {
                          future = open();
                        }),
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : const CircularProgressIndicator(),
        ),
      );
    },
  );
}
