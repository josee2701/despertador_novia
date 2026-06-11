import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:despertador_novia/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Widget tests - Pantalla principal', () {
    testWidgets('Muestra mensaje de estado vacío cuando no hay alarmas', (WidgetTester tester) async {
      await tester.pumpWidget(const MiDespertadorApp());
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('No tienes alarmas'), findsOneWidget);
      expect(find.text('Toca el botón azul para crear tu primera alarma'), findsOneWidget);
    });

    testWidgets('Muestra botón de agregar alarma', (WidgetTester tester) async {
      await tester.pumpWidget(const MiDespertadorApp());
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Nueva alarma'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('Muestra título de la pantalla', (WidgetTester tester) async {
      await tester.pumpWidget(const MiDespertadorApp());
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Mis Alarmas'), findsOneWidget);
    });
  });
}
