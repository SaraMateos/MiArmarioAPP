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
  throw TestFailure('La interfaz no ha llegado al estado esperado.');
}
