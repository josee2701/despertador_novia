import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../utils/constantes.dart';

/// Contrato mínimo para programar y cancelar notificaciones locales.
///
/// Existe para que [RecordatorioService] pueda probarse sin el plugin nativo,
/// igual que `AppOpenAdManager` separa su política de su plumbing.
abstract class PlanificadorNotificaciones {
  Future<void> inicializar();

  Future<void> programar({
    required int id,
    required String titulo,
    required String cuerpo,
    required DateTime cuando,
  });

  Future<void> cancelar(int id);
}

/// Implementación real sobre `flutter_local_notifications`.
///
/// Es deliberadamente una notificación y no una alarma del package `alarm`:
/// programar el recordatorio con `Alarm.set` arrancaba un foreground service
/// que nunca se detenía y dejaba `ringingAlarmIds` ocupado, con lo que la
/// alarma real se descartaba 30 minutos después.
class PlanificadorLocalNotifications implements PlanificadorNotificaciones {
  PlanificadorLocalNotifications([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _inicializado = false;

  static const NotificationDetails _detalles = NotificationDetails(
    android: AndroidNotificationDetails(
      canalRecordatorios,
      'Recordatorios de alarma',
      channelDescription:
          'Aviso 30 minutos antes de que suene tu alarma. Silencioso.',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      playSound: false,
      enableVibration: false,
    ),
  );

  @override
  Future<void> inicializar() async {
    if (_inicializado) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(await _nombreZonaHoraria()));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _inicializado = true;
  }

  /// Nombre IANA de la zona horaria del dispositivo.
  Future<String> _nombreZonaHoraria() async {
    final zona = await FlutterTimezone.getLocalTimezone();
    return zona.identifier;
  }

  @override
  Future<void> programar({
    required int id,
    required String titulo,
    required String cuerpo,
    required DateTime cuando,
  }) async {
    await inicializar();
    await _plugin.zonedSchedule(
      id: id,
      title: titulo,
      body: cuerpo,
      scheduledDate: tz.TZDateTime.from(cuando, tz.local),
      notificationDetails: _detalles,
      // Inexacta a propósito: 30 minutos no necesitan precisión al segundo y
      // así no consume cuota de alarmas exactas ni compite con la alarma real.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> cancelar(int id) async {
    await inicializar();
    await _plugin.cancel(id: id);
  }
}
