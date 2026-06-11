import 'dart:io';

import 'package:permission_handler/permission_handler.dart';
import 'package:do_not_disturb/do_not_disturb.dart';

/// Servicio encargado de verificar y solicitar permisos del sistema.
///
/// Maneja dos tipos de permisos:
/// 1. SCHEDULE_EXACT_ALARM: necesario en Android 12+ para alarmas exactas.
/// 2. Modo No Molestar: verifica si está activo, lo que podría silenciar la alarma.
class PermissionService {
  final _dndPlugin = DoNotDisturbPlugin();

  /// Comprueba si la app tiene permiso para programar alarmas exactas.
  ///
  /// Retorna true si el permiso ya está concedido.
  /// Retorna false si no se necesita (iOS/desktop) o si falta el permiso.
  Future<bool> verificarPermisoAlarmasExactas() async {
    if (!Platform.isAndroid) return true;
    return Permission.scheduleExactAlarm.isGranted;
  }

  /// Solicita al usuario el permiso de alarmas exactas.
  Future<void> solicitarPermisoAlarmasExactas() async {
    if (Platform.isAndroid) {
      await Permission.scheduleExactAlarm.request();
    }
  }

  /// Verifica si el modo No Molestar está activo en Android.
  ///
  /// Retorna false en plataformas que no soportan esta verificación.
  Future<bool> verificarModoNoMolestar() async {
    if (!Platform.isAndroid) return false;
    return _dndPlugin.isDndEnabled();
  }

  /// Verifica si el permiso de notificaciones está concedido (Android 13+).
  Future<bool> verificarPermisoNotificaciones() async {
    if (!Platform.isAndroid) return true;
    return Permission.notification.isGranted;
  }

  /// Solicita el permiso de notificaciones en tiempo de ejecución.
  Future<void> solicitarPermisoNotificaciones() async {
    if (Platform.isAndroid) {
      await Permission.notification.request();
    }
  }

  /// Solicita permisos y abre ajustes si fueron denegados permanentemente.
  Future<void> verificarYSolicitarPermisoAlarmasExactas() async {
    if (!Platform.isAndroid) return;
    final status = await Permission.scheduleExactAlarm.status;
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    } else {
      await Permission.scheduleExactAlarm.request();
    }
  }

  /// Abre la configuración del sistema para que el usuario cambie permisos.
  Future<void> abrirConfiguracion() async {
    await openAppSettings();
  }

  /// Verifica si la app está excluida de las optimizaciones de batería.
  Future<bool> verificarExencionBateria() async {
    if (!Platform.isAndroid) return true;
    return Permission.ignoreBatteryOptimizations.isGranted;
  }

  /// Solicita al usuario excluir la app de las optimizaciones de batería.
  Future<void> solicitarExencionBateria() async {
    if (!Platform.isAndroid) return;
    await Permission.ignoreBatteryOptimizations.request();
  }
}
