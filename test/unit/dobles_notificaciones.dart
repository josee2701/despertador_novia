import 'package:despertador_novia/services/planificador_notificaciones.dart';

/// Planificador en memoria para las pruebas. No toca el plugin nativo.
class PlanificadorFalso implements PlanificadorNotificaciones {
  /// ID de notificación → momento programado.
  final Map<int, DateTime> programados = {};

  /// IDs cancelados, en orden.
  final List<int> cancelados = [];

  /// Cuerpos de las notificaciones programadas, por ID.
  final Map<int, String> cuerpos = {};

  /// Si es true, `programar` y `cancelar` lanzan para probar el camino de error.
  bool fallar = false;

  @override
  Future<void> inicializar() async {}

  @override
  Future<void> programar({
    required int id,
    required String titulo,
    required String cuerpo,
    required DateTime cuando,
  }) async {
    if (fallar) throw StateError('fallo simulado del planificador');
    programados[id] = cuando;
    cuerpos[id] = cuerpo;
  }

  @override
  Future<void> cancelar(int id) async {
    if (fallar) throw StateError('fallo simulado del planificador');
    programados.remove(id);
    cancelados.add(id);
  }
}
