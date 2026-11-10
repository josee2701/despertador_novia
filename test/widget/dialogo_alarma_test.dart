import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:despertador_novia/models/alarma.dart';
import 'package:despertador_novia/widgets/dialogo_alarma.dart';

Future<void> _pantallaGrande(WidgetTester t) async {
  t.view.physicalSize = const Size(1200, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

Widget _app(Widget dialogo) => MaterialApp(home: Scaffold(body: dialogo));

({int h, int m, String e, List<int> d})? _ultimo;

DialogoAlarma _crear({Alarma? alarma}) {
  _ultimo = null;
  return DialogoAlarma(
    alarma: alarma,
    onGuardar: (h, m, e, d) => _ultimo = (h: h, m: m, e: e, d: d),
  );
}

Future<void> _abrirConfig(WidgetTester t) async {
  await t.tap(find.text('Repetición y nombre'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('modo crear: título, paso simple y Listo guarda sin días', (
    t,
  ) async {
    await t.pumpWidget(_app(_crear()));
    expect(find.text('Nueva alarma'), findsOneWidget);
    expect(find.text('Listo'), findsOneWidget);
    expect(find.text('Repetición y nombre'), findsOneWidget);
    expect(find.text('Repetir'), findsNothing);

    await t.tap(find.text('Listo'));
    expect(_ultimo, isNotNull);
    expect(_ultimo!.d, isEmpty);
  });

  testWidgets('seleccionar y deseleccionar días, ordenados', (t) async {
    await _pantallaGrande(t);
    await t.pumpWidget(_app(_crear()));
    await _abrirConfig(t);
    expect(find.text('Alarma de una sola vez'), findsOneWidget);

    await t.tap(find.text('Mié'));
    await t.tap(find.text('Lun'));
    await t.pump();
    expect(find.text('Se repite en los días seleccionados'), findsOneWidget);

    await t.tap(find.text('Guardar'));
    expect(_ultimo!.d, [1, 3]);

    await t.tap(find.text('Lun'));
    await t.tap(find.text('Mié'));
    await t.pump();
    expect(find.text('Alarma de una sola vez'), findsOneWidget);
    await t.tap(find.text('Guardar'));
    expect(_ultimo!.d, isEmpty);
  });

  testWidgets('chips rápidos fijan los días', (t) async {
    await _pantallaGrande(t);
    await t.pumpWidget(_app(_crear()));
    await _abrirConfig(t);

    await t.tap(find.text('Lun–Vie'));
    await t.tap(find.text('Guardar'));
    expect(_ultimo!.d, [1, 2, 3, 4, 5]);

    await t.tap(find.text('Todos'));
    await t.tap(find.text('Guardar'));
    expect(_ultimo!.d, [1, 2, 3, 4, 5, 6, 7]);

    await t.tap(find.text('Fin de semana'));
    await t.tap(find.text('Guardar'));
    expect(_ultimo!.d, [6, 7]);
  });

  testWidgets('editar muestra horaDelDia/minutoDelDia, no hora', (t) async {
    await _pantallaGrande(t);
    final alarma =
        Alarma(
            id: 1,
            hora: DateTime(2030, 1, 1, 15, 45), // hora de snooze
            etiqueta: 'Trabajo',
            pospuesta: true,
            diasSemana: [1, 2],
          )
          ..horaDelDia = 7
          ..minutoDelDia = 5;
    await t.pumpWidget(_app(_crear(alarma: alarma)));

    expect(find.text('Editar alarma'), findsOneWidget);
    expect(find.text('7:05 AM'), findsOneWidget);
    expect(find.text('3:45 PM'), findsNothing);
    // Con días, abre directamente el paso completo.
    expect(find.text('Trabajo'), findsOneWidget);

    await t.tap(find.text('Guardar'));
    expect(_ultimo!.h, 7);
    expect(_ultimo!.m, 5);
    expect(_ultimo!.e, 'Trabajo');
    expect(_ultimo!.d, [1, 2]);
  });
}
