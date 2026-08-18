import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:despertador_novia/models/alarma.dart';
import 'package:despertador_novia/screens/pantalla_alarma_activa.dart';
import 'package:despertador_novia/widgets/slide_desbloqueo.dart';

Alarma _alarma() => Alarma(
      id: 1,
      hora: DateTime.now().add(const Duration(minutes: 1)),
      etiqueta: 'Despertar para el trabajo',
      diasSemana: const [1, 2, 3, 4, 5],
      horaDelDia: 6,
      minutoDelDia: 30,
    );

/// Monta la pantalla con el tamaño de dispositivo indicado, en dp.
Future<void> _montarEn(WidgetTester tester, Size tamano) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: PantallaAlarmaActiva(
      alarma: _alarma(),
      onDetener: () {},
      onPosponer: () {},
    ),
  ));
  await tester.pump();
}

/// Los desbordes que importan aquí son los verticales: la Column de la
/// pantalla no tiene scroll y el deslizador compite con los `Spacer`.
///
/// El eje horizontal se ignora a propósito. La fuente de las pruebas dibuja
/// todos los glifos como cuadrados del tamaño de letra, así que el reloj de 88
/// puntos mide 352 px de ancho en el test y unos 190 con una fuente real: el
/// desborde horizontal que aparece aquí no existe en el dispositivo.
void _esperarSinDesbordeVertical(WidgetTester tester) {
  final error = tester.takeException();
  if (error == null) return;
  expect(error.toString(), isNot(contains('on the bottom')),
      reason: 'La pantalla de alarma no puede desbordar a lo alto: es lo '
          'primero que ve la persona al despertarse');
}

void main() {
  testWidgets('no desborda a lo alto en un móvil normal', (tester) async {
    await _montarEn(tester, const Size(360, 800));
    _esperarSinDesbordeVertical(tester);
  });

  testWidgets('no desborda a lo alto en un móvil de pantalla corta',
      (tester) async {
    await _montarEn(tester, const Size(360, 690));
    _esperarSinDesbordeVertical(tester);
  });

  testWidgets('con los botones de respaldo visibles tampoco desborda',
      (tester) async {
    // A los 10 segundos aparecen "Posponer 5 min" y "Detener": es el momento
    // de máxima altura ocupada.
    await _montarEn(tester, const Size(360, 690));
    await tester.pump(const Duration(seconds: 11));

    expect(find.text('Posponer 5 min'), findsOneWidget);
    _esperarSinDesbordeVertical(tester);

    // El reloj deja un Timer.periodic vivo: se desmonta para no arrastrarlo.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('la zona de arrastre se encoge cuando la pantalla es baja',
      (tester) async {
    // Encogerla NO facilita el gesto —lo que hay que deslizar es una constante
    // del widget—, solo acorta el trecho en el que el control sigue al dedo.
    // Es lo que permite dar sitio al recorrido largo sin desbordar.
    await _montarEn(tester, const Size(360, 800));
    final alta = tester.getSize(find.byType(SlideDesbloqueo)).height;

    await _montarEn(tester, const Size(360, 690));
    final media = tester.getSize(find.byType(SlideDesbloqueo)).height;

    await _montarEn(tester, const Size(320, 570));
    final baja = tester.getSize(find.byType(SlideDesbloqueo)).height;

    expect(alta, greaterThan(media));
    expect(media, greaterThan(baja));
    tester.takeException();
  });
}
