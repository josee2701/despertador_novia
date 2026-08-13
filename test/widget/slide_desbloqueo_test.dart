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

void main() {
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
