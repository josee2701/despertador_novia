import 'dart:async';

import '../models/alarma.dart';
import '../utils/date_utils.dart';
import 'log_service.dart';
import 'planificador_notificaciones.dart';

/// Programa el aviso "tu alarma suena en 30 minutos" como notificación local.
///
/// Reemplaza al antiguo `AlarmService.programarRecordatorio`, que usaba
/// `Alarm.set` y acababa descartando la alarma real.
class RecordatorioService {
  RecordatorioService({
    PlanificadorNotificaciones? planificador,
    void Function(String evento)? registro,
  })  : _planificador = planificador ?? PlanificadorLocalNotifications(),
        _registro = registro ??
            ((evento) => unawaited(LogService.instancia.registrar(evento)));

  final PlanificadorNotificaciones _planificador;
  final void Function(String evento) _registro;

  /// Desplazamiento del ID de alarma para obtener el ID de notificación.
  /// Evita colisionar con las notificaciones que el package `alarm` publica
  /// usando el ID de alarma tal cual.
  static const int offsetNotificacion = 10000;

  /// Cuánto antes del disparo se avisa.
  static const Duration antelacion = Duration(minutes: 30);

  /// Programa el recordatorio de [alarma], si procede.
  ///
  /// Se omite en dos casos, ambos registrados en el log de diagnóstico:
  /// la alarma está pospuesta (su hora es temporal) o falta menos de la
  /// [antelacion] para que suene.
  Future<void> programar(Alarma alarma) async {
    if (alarma.pospuesta) {
      _registro('Recordatorio 30 min OMITIDO para alarma #${alarma.id}: '
          'pospuesta (snooze)');
      return;
    }

    final momento = alarma.hora.subtract(antelacion);
    if (!momento.isAfter(DateTime.now())) {
      _registro('Recordatorio 30 min OMITIDO para alarma #${alarma.id}: '
          'faltan menos de 30 min para el disparo');
      return;
    }

    final horaTexto = formatearHoraAMPM(
      DateTime(2000, 1, 1, alarma.horaDelDia, alarma.minutoDelDia),
    );

    try {
      await _planificador.programar(
        id: alarma.id + offsetNotificacion,
        titulo: 'Mi Despertador',
        cuerpo: '${alarma.etiqueta} suena en 30 minutos ($horaTexto)',
        cuando: momento,
      );
      _registro('Recordatorio 30 min programado para alarma #${alarma.id} '
          '(${formatearHoraAMPM(momento)})');
    } catch (e) {
      _registro('⚠ ERROR al programar recordatorio de alarma #${alarma.id}: $e');
    }
  }

  /// Cancela el recordatorio de [alarmaId]. Seguro si no había ninguno.
  Future<void> cancelar(int alarmaId) async {
    try {
      await _planificador.cancelar(alarmaId + offsetNotificacion);
    } catch (e) {
      _registro('⚠ ERROR al cancelar recordatorio de alarma #$alarmaId: $e');
    }
  }
}
