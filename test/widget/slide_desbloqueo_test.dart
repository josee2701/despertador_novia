import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:despertador_novia/widgets/slide_desbloqueo.dart';

/// Traduce el texto de dirección que emite el widget a un vector de arrastre
/// de la magnitud indicada.
Offset _vector(String texto, double magnitud) {
  if (texto.contains('derecha')) return Offset(magnitud, 0);
  if (texto.contains('izquierda')) return Offset(-magnitud, 0);
  if (texto.contains('abajo')) return Offset(0, magnitud);
  return Offset(0, -magnitud);
}


/// Monta el widget hasta que salga la orientación pedida —la dirección es
/// aleatoria entre cuatro y no se puede imponer—, arrastra [distancia] px en
/// esa dirección y devuelve si eso bastó para desbloquear.
int _montajes = 0;

Future<bool> _desbloqueaCon(
  WidgetTester tester, {
  required bool vertical,
  required double distancia,
  double ancho = 400,
}) async {
  for (var intento = 0; intento < 80; intento++) {
    // Clave única por montaje, no por intento: con dos llamadas seguidas en el
    // mismo test, repetir la clave hace que Flutter reutilice el State —el del
    // gesto ya completado— y el widget nunca vuelve a desbloquear.
    _montajes++;
    var desbloqueado = false;
    var direccion = '';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        key: ValueKey(_montajes),
        body: SizedBox(
          width: ancho,
          child: SlideDesbloqueo(
            onDesbloqueado: () => desbloqueado = true,
            onDireccionCambiada: (d) => direccion = d,
          ),
        ),
      ),
    ));
    await tester.pump();

    final esVertical =
        direccion.contains('arriba') || direccion.contains('abajo');
    if (esVertical != vertical) continue;

    final gesto = await tester.startGesture(
        tester.getCenter(find.byType(SlideDesbloqueo)));
    // En varios tramos, como un arrastre real.
    for (var i = 0; i < 5; i++) {
      await gesto.moveBy(_vector(direccion, distancia / 5));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesto.up();
    await tester.pump();
    await tester.pumpAndSettle();
    return desbloqueado;
  }
  fail('No salió una dirección ${vertical ? "vertical" : "horizontal"}');
}

void main() {
  testWidgets('un roce corto NO apaga la alarma, venga por donde venga',
      (tester) async {
    // El recorrido vertical se calculaba sobre una constante de 80 px, asi que
    // con el umbral habitual (0.75) la alarma se apagaba con 24 px de
    // arrastre, frente a los 82-109 px del horizontal segun el ancho. Un roce
    // de alguien medio dormido bastaba, en la unica pantalla que no debe poder
    // descartarse por accidente, y salia vertical la mitad de las veces.
    expect(await _desbloqueaCon(tester, vertical: true, distancia: 40), isFalse,
        reason: '40 px verticales no pueden apagar una alarma');
    expect(await _desbloqueaCon(tester, vertical: false, distancia: 40), isFalse,
        reason: 'Referencia: en horizontal 40 px nunca bastaron');
  });

  testWidgets('un deslizamiento franco SÍ apaga la alarma', (tester) async {
    // La otra cara: subir la exigencia no puede dejar el gesto inalcanzable.
    // Con 400 px de ancho el horizontal pide 120 px y el vertical 98.
    expect(await _desbloqueaCon(tester, vertical: true, distancia: 140), isTrue,
        reason: 'Un arrastre vertical franco tiene que completarse');
    expect(await _desbloqueaCon(tester, vertical: false, distancia: 140), isTrue,
        reason: 'Y el horizontal seguir funcionando igual que antes');
  });

  testWidgets('un segundo arrastre durante el reset no se descarta',
      (tester) async {
    var desbloqueado = false;
    var direccion = '';

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          child: SlideDesbloqueo(
            onDesbloqueado: () => desbloqueado = true,
            onDireccionCambiada: (d) => direccion = d,
          ),
        ),
      ),
    ));
    await tester.pump();

    final centro = tester.getCenter(find.byType(SlideDesbloqueo));

    // Primer arrastre corto en la dirección correcta: 10px no alcanza el
    // umbral ni siquiera en la rama vertical (tope de 32px), y dispara la
    // animación de reset de 300 ms.
    final gesto1 = await tester.startGesture(centro);
    await gesto1.moveBy(_vector(direccion, 10));
    await gesto1.up();
    await tester.pump(const Duration(milliseconds: 50));

    // Segundo arrastre mientras el reset sigue animando (250 ms restantes).
    // Se reparte en varios frames, cada uno con su propio pump, para que el
    // listener de la animación tenga ocasión de pisar `_arrastre` en cada
    // tick si el reset no se detiene — igual que en un arrastre real, donde
    // los onPanUpdate no llegan todos en el mismo frame.
    final gesto2 = await tester.startGesture(centro);
    for (var i = 0; i < 4; i++) {
      await gesto2.moveBy(_vector(direccion, 50));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await gesto2.up();
    await tester.pump();

    expect(desbloqueado, isTrue,
        reason: 'El arrastre durante el reset debe contar, no descartarse');

    await tester.pumpAndSettle();
  });
}
