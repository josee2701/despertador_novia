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
  /// Desplazamiento aplicado al ID de alarma para generar IDs de recordatorio.
  ///
  /// IDs reales: 1–9999. IDs de recordatorio: 10001–19999.
  /// Usar [esIdRecordatorio] para comprobar si un ID pertenece a un recordatorio.
  static const int offsetRecordatorio = 10000;

  /// Devuelve true si el [id] pertenece a un recordatorio (no a una alarma real).
  static bool esIdRecordatorio(int id) => id > offsetRecordatorio;

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
    );
  }

  /// Programa una alarma nativa en el sistema.
  ///
  /// Si la alarma ya existía, la reemplaza con la nueva configuración.
  Future<void> programar(Alarma alarma) async {
    await Alarm.set(alarmSettings: crearConfiguracion(alarma));
  }

  /// Programa un recordatorio silencioso 30 minutos antes del disparo de [alarma].
  ///
  /// Solo se programa si quedan más de 30 minutos para la alarma y la alarma
  /// no está en modo snooze ([Alarma.pospuesta]). Si el recordatorio ya pasó o
  /// la condición no se cumple, la llamada no hace nada.
  Future<void> programarRecordatorio(Alarma alarma) async {
    // No programar recordatorios para alarmas en snooze: tienen hora temporal.
    if (alarma.pospuesta) return;

    final idRecordatorio = alarma.id + offsetRecordatorio;
    final momentoRecordatorio = alarma.hora.subtract(const Duration(minutes: 30));

    // No programar si el momento ya pasó o es ahora mismo.
    if (!momentoRecordatorio.isAfter(DateTime.now())) return;

    final horaTexto = formatearHoraAMPM(
      DateTime(2000, 1, 1, alarma.horaDelDia, alarma.minutoDelDia),
    );

    await Alarm.set(
      alarmSettings: AlarmSettings(
        id: idRecordatorio,
        dateTime: momentoRecordatorio,
        // El package requiere un audio path; se usa el mismo WAV pero con
        // volumen 0 para que sea completamente silencioso.
        assetAudioPath: archivoSonido,
        volumeSettings: const VolumeSettings.fixed(
          volume: 0,
          volumeEnforced: false,
        ),
        notificationSettings: NotificationSettings(
          title: 'Mi Despertador',
          body: '${alarma.etiqueta} suena en 30 minutos ($horaTexto)',
          stopButton: 'Cancelar',
        ),
        loopAudio: false,
        vibrate: false,
        androidFullScreenIntent: false,
        warningNotificationOnKill: false,
      ),
    );
  }

  /// Cancela el recordatorio asociado a [alarmaId].
  ///
  /// Es seguro llamar aunque no exista un recordatorio programado.
  Future<void> cancelarRecordatorio(int alarmaId) async {
    await Alarm.stop(alarmaId + offsetRecordatorio);
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
