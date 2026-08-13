import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:despertador_novia/models/alarma.dart';
import 'package:despertador_novia/widgets/tarjeta_alarma.dart';

Widget _envolver(Alarma alarma) {
  return MaterialApp(
    home: Scaffold(
      body: TarjetaAlarma(
        alarma: alarma,
        onToggle: (_) {},
        onEliminar: () {},
        onTap: () {},
      ),
    ),
  );
}

void main() {
  testWidgets('muestra HOY en una alarma activa que dispara hoy', (tester) async {
    final dentroDeUnaHora = DateTime.now().add(const Duration(hours: 1));
    final alarma = Alarma(
      id: 1,
      hora: dentroDeUnaHora,
      etiqueta: 'Mañana',
      activa: true,
      horaDelDia: dentroDeUnaHora.hour,
      minutoDelDia: dentroDeUnaHora.minute,
    );

    await tester.pumpWidget(_envolver(alarma));

    expect(find.text('HOY'), findsOneWidget);
  });

  testWidgets('no muestra HOY en una alarma desactivada', (tester) async {
    final dentroDeUnaHora = DateTime.now().add(const Duration(hours: 1));
    final alarma = Alarma(
      id: 2,
      hora: dentroDeUnaHora,
      etiqueta: 'Apagada',
      activa: false,
      horaDelDia: dentroDeUnaHora.hour,
      minutoDelDia: dentroDeUnaHora.minute,
    );

    await tester.pumpWidget(_envolver(alarma));

    expect(find.text('HOY'), findsNothing);
  });

  testWidgets('no muestra HOY en una alarma activa que dispara mañana',
      (tester) async {
    final manana = DateTime.now().add(const Duration(days: 1, hours: 1));
    final alarma = Alarma(
      id: 3,
      hora: manana,
      etiqueta: 'Mañana',
      activa: true,
      horaDelDia: manana.hour,
      minutoDelDia: manana.minute,
    );

    await tester.pumpWidget(_envolver(alarma));

    expect(find.text('HOY'), findsNothing);
  });

  testWidgets('no muestra HOY en una alarma inactiva con hora pasada',
      (tester) async {
    final haceUnaHora = DateTime.now().subtract(const Duration(hours: 1));
    final alarma = Alarma(
      id: 4,
      hora: haceUnaHora,
      etiqueta: 'Vencida',
      activa: false,
      horaDelDia: haceUnaHora.hour,
      minutoDelDia: haceUnaHora.minute,
    );

    await tester.pumpWidget(_envolver(alarma));

    expect(find.text('HOY'), findsNothing);
  });
}
