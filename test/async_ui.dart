import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Allow real SQLite/file I/O to finish without advancing a loading animation
/// through ten virtual minutes with pumpAndSettle.
Future<void> waitForWidget(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 250; attempt++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty &&
        find.byType(LinearProgressIndicator).evaluate().isEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  final frameworkException = tester.takeException();
  final visibleTexts = find
      .byType(Text)
      .evaluate()
      .map((element) => (element.widget as Text).data)
      .whereType<String>()
      .take(80)
      .join(' | ');
  throw TestFailure(
    'La interfaz no ha llegado al estado esperado. '
    'Elemento buscado: $finder. '
    'Coincidencias: ${finder.evaluate().length}. '
    'Indicadores circulares: '
    '${find.byType(CircularProgressIndicator).evaluate().length}. '
    'Indicadores lineales: '
    '${find.byType(LinearProgressIndicator).evaluate().length}. '
    'Scaffold: ${find.byType(Scaffold).evaluate().length}. '
    'Textos presentes: [$visibleTexts]. '
    'Excepción de Flutter: $frameworkException',
  );
}
