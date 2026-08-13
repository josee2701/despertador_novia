import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';

import '../models/alarma.dart';
import '../utils/constantes.dart';
import '../utils/date_utils.dart';
import 'log_service.dart';

/// Servicio que interactúa con el package `alarm` para programar y detener
/// alarmas nativas en el dispositivo.
///
/// Este servicio traduce un modelo [Alarma] a [AlarmSettings] y delega
/// la programación real al package nativo.
class AlarmService {
  AlarmService({void Function(String evento)? registro})
      : _registro = registro ??
            ((evento) => unawaited(LogService.instancia.registrar(evento)));

  /// Sumidero del log de diagnóstico. Inyectable para poder verificar en las
  /// pruebas que los errores de programación quedan registrados.
  final void Function(String evento) _registro;

  /// Inicializa el package alarm. Debe llamarse antes de cualquier otra operación.
  Future<void> init() async {
    await Alarm.init();
    await Alarm.setWarningNotificationOnKill(
      'Tus alarmas pueden no sonar',
      'Cerraste la app. Ábrela de nuevo para que tus alarmas se reprogramen.',
    );
  }

  /// Crea la configuración nativa a partir de un modelo [Alarma].
  ///
  /// El [stopButton] llama a [Alarm.stop] internamente (no pasa por nuestro
  /// presenter). Por eso [onAppResumed] verifica con [alarmIsRinging] si la
  /// alarma sigue sonando al volver a foreground y reprograma si es recurrente.
  AlarmSettings crearConfiguracion(Alarma alarma) {
    final horaTexto = formatearHoraAMPM(
      DateTime(2000, 1, 1, alarma.horaDelDia, alarma.minutoDelDia),
    );
    return AlarmSettings(
      id: alarma.id,
      dateTime: alarma.hora,
      assetAudioPath: archivoSonido,
      volumeSettings: const VolumeSettings.fixed(
        volume: 1.0,
        volumeEnforced: true,
      ),
      notificationSettings: NotificationSettings(
        title: 'Mi Despertador',
        body: alarma.pospuesta
            ? '${alarma.etiqueta} — Pospuesta (${formatearHoraAMPM(alarma.hora)})'
            : '${alarma.etiqueta} — $horaTexto',
        stopButton: 'Detener',
      ),
      loopAudio: true,
      vibrate: true,
      androidFullScreenIntent: true,
      // Mostrar advertencia si el OS mata la app, mejora fiabilidad en Android agresivos.
      warningNotificationOnKill: true,
      // CRÍTICO: por defecto el package detiene la alarma cuando el usuario quita
      // la app de "Recientes" (onTaskRemoved → stopSelf), apagando el sonido a
      // los 1-2s. Con false el foreground service sigue sonando aunque se quite
      // la app de Recientes. El botón "Detener" de la notificación sigue funcionando.
      androidStopAlarmOnTermination: false,
    );
  }

  /// Programa una alarma nativa en el sistema.
  ///
  /// Si la alarma ya existía, la reemplaza con la nueva configuración.
  Future<void> programar(Alarma alarma) async {
    try {
      await Alarm.set(alarmSettings: crearConfiguracion(alarma));
    } catch (e) {
      _registro('⚠ ERROR al programar alarma #${alarma.id} '
          '"${alarma.etiqueta}": $e');
      rethrow;
    }
  }

  /// Detiene una alarma nativa por su ID.
  Future<void> detener(int id) async {
    await Alarm.stop(id);
  }

  /// Devuelve true si la alarma con ese ID está sonando en este momento.
  Future<bool> alarmIsRinging(int id) => Alarm.isRinging(id);

  /// Devuelve todas las alarmas actualmente programadas en el paquete nativo.
  Future<List<AlarmSettings>> getAlarmasNativas() => Alarm.getAlarms();

  /// Escucha el stream de alarmas que están sonando actualmente.
  Stream<AlarmSet> get ringingStream => Alarm.ringing;
}
