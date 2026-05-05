import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';

import '../models/alarma.dart';
import '../utils/constantes.dart';
import '../utils/date_utils.dart';

/// Servicio que interactúa con el package `alarm` para programar y detener
/// alarmas nativas en el dispositivo.
///
/// Este servicio traduce un modelo [Alarma] a [AlarmSettings] y delega
/// la programación real al package nativo.
class AlarmService {
  /// Inicializa el package alarm. Debe llamarse antes de cualquier otra operación.
  Future<void> init() async {
    await Alarm.init();
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
        body: '${alarma.etiqueta} — $horaTexto',
        stopButton: 'Detener',
      ),
      loopAudio: true,
      vibrate: true,
      androidFullScreenIntent: true,
      warningNotificationOnKill: false,
    );
  }

  /// Programa una alarma nativa en el sistema.
  ///
  /// Si la alarma ya existía, la reemplaza con la nueva configuración.
  Future<void> programar(Alarma alarma) async {
    await Alarm.set(alarmSettings: crearConfiguracion(alarma));
  }

  /// Detiene una alarma nativa por su ID.
  Future<void> detener(int id) async {
    await Alarm.stop(id);
  }

  /// Devuelve true si la alarma con ese ID está sonando en este momento.
  Future<bool> alarmIsRinging(int id) => Alarm.isRinging(id);

  /// Escucha el stream de alarmas que están sonando actualmente.
  Stream<AlarmSet> get ringingStream => Alarm.ringing;
}
