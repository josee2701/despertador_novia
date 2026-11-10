import 'package:flutter_test/flutter_test.dart';

import 'package:despertador_novia/services/planificador_notificaciones.dart';

/// Subclase de test que sustituye el trabajo real de inicialización (que
/// tocaría el plugin nativo y el canal de plataforma) por un contador, para
/// poder verificar cuántas veces se ejecuta sin depender de ese canal.
class _PlanificadorContador extends PlanificadorLocalNotifications {
  int vecesInicializado = 0;
  bool fallar = false;

  @override
  Future<void> ejecutarInicializacion() async {
    // Cede el turno para forzar que dos llamadas concurrentes se solapen
    // mientras esta "inicialización" sigue en curso, igual que ocurriría con
    // los `await` reales de timezone/plugin nativo.
    await Future<void>.delayed(Duration.zero);
    vecesInicializado++;
    if (fallar) throw StateError('fallo simulado de inicialización');
  }
}

void main() {
  test(
      'dos llamadas concurrentes a inicializar() ejecutan el trabajo real una sola vez',
      () async {
    final planificador = _PlanificadorContador();

    await Future.wait([
      planificador.inicializar(),
      planificador.inicializar(),
    ]);

    expect(planificador.vecesInicializado, 1);
  });

  test('un fallo de inicialización permite reintentar en la siguiente llamada',
      () async {
    final planificador = _PlanificadorContador()..fallar = true;

    await expectLater(planificador.inicializar(), throwsA(isA<StateError>()));

    planificador.fallar = false;
    await planificador.inicializar();

    expect(planificador.vecesInicializado, 2);
  });
}
