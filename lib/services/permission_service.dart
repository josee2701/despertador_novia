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

  /// Abre la configuración del sistema para que el usuario cambie permisos.
  Future<void> abrirConfiguracion() async {
    await openAppSettings();
  }
}
