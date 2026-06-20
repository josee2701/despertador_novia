import 'dart:io';

import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:do_not_disturb/do_not_disturb.dart';

/// Servicio encargado de verificar y solicitar permisos del sistema.
///
/// Maneja dos tipos de permisos:
/// 1. SCHEDULE_EXACT_ALARM: necesario en Android 12+ para alarmas exactas.
/// 2. Modo No Molestar: verifica si está activo, lo que podría silenciar la alarma.
class PermissionService {
  final _dndPlugin = DoNotDisturbPlugin();

  /// Canal nativo hacia MainActivity.kt (full-screen intent + Autostart OEM).
  static const MethodChannel _canalSistema =
      MethodChannel('mi_despertador/sistema');

  /// Fabricantes con gestión de batería agresiva que matan el proceso de la app
  /// y bloquean alarmas si no se activa el "Inicio automático" manualmente.
  static const _fabricantesAgresivos = {
    'xiaomi', 'redmi', 'poco', 'huawei', 'honor',
    'oppo', 'vivo', 'realme', 'oneplus', 'meizu',
  };

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

  /// Comprueba si la app puede mostrar pantallas a pantalla completa sobre el
  /// lockscreen (full-screen intent).
  ///
  /// En Android < 14 siempre true. En Android 14+ el usuario debe concederlo
  /// manualmente: es la causa #1 de "no aparece la pantalla con el teléfono
  /// bloqueado" en dispositivos modernos y en MIUI.
  Future<bool> verificarFullScreenIntent() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _canalSistema
              .invokeMethod<bool>('puedeUsarFullScreenIntent') ??
          true;
    } on PlatformException {
      return true; // No bloquear si el canal falla.
    }
  }

  /// Abre el ajuste del sistema para conceder full-screen intent.
  Future<void> abrirAjustesFullScreenIntent() async {
    if (!Platform.isAndroid) return;
    try {
      await _canalSistema.invokeMethod('abrirAjustesFullScreenIntent');
    } on PlatformException {
      await openAppSettings(); // Fallback a ajustes de la app.
    }
  }

  /// Abre la pantalla de "Inicio automático" del fabricante (MIUI, EMUI, etc.).
  ///
  /// Sin esto, dispositivos Xiaomi/Huawei/Oppo matan el proceso y las alarmas
  /// no suenan. No hay forma de activarlo programáticamente: solo se abre la
  /// pantalla y se instruye al usuario.
  Future<void> abrirAutostartOEM() async {
    if (!Platform.isAndroid) return;
    try {
      await _canalSistema.invokeMethod('abrirAutostartOEM');
    } on PlatformException {
      await openAppSettings();
    }
  }

  /// True si el fabricante del dispositivo mata apps de forma agresiva y por
  /// tanto conviene mostrar la guía de Inicio automático.
  Future<bool> esFabricanteAgresivo() async {
    if (!Platform.isAndroid) return false;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return _fabricantesAgresivos.contains(info.manufacturer.toLowerCase());
    } on PlatformException {
      return false;
    }
  }

  /// Devuelve una descripción legible del dispositivo (marca, modelo, Android).
  Future<String> descripcionDispositivo() async {
    if (!Platform.isAndroid) {
      return Platform.operatingSystem;
    }
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return '${info.manufacturer} ${info.model} '
          '— Android ${info.version.release} (SDK ${info.version.sdkInt})';
    } on PlatformException {
      return 'Android (desconocido)';
    }
  }

  /// Captura el estado actual de todos los permisos críticos.
  ///
  /// Se usa tanto en la pantalla de diagnóstico como en el reporte que el
  /// usuario comparte. Cada clave es legible para humanos.
  Future<EstadoPermisos> obtenerEstadoPermisos() async {
    if (!Platform.isAndroid) {
      return const EstadoPermisos(
        alarmasExactas: true,
        notificaciones: true,
        exencionBateria: true,
        fullScreenIntent: true,
        noMolestar: false,
      );
    }
    return EstadoPermisos(
      alarmasExactas: await Permission.scheduleExactAlarm.isGranted,
      notificaciones: await Permission.notification.isGranted,
      exencionBateria: await Permission.ignoreBatteryOptimizations.isGranted,
      fullScreenIntent: await verificarFullScreenIntent(),
      noMolestar: await _dndPlugin.isDndEnabled(),
    );
  }
}

/// Instantánea del estado de los permisos del sistema relevantes para las alarmas.
class EstadoPermisos {
  final bool alarmasExactas;
  final bool notificaciones;
  final bool exencionBateria;
  final bool fullScreenIntent;
  final bool noMolestar;

  const EstadoPermisos({
    required this.alarmasExactas,
    required this.notificaciones,
    required this.exencionBateria,
    required this.fullScreenIntent,
    required this.noMolestar,
  });

  /// True si todos los permisos necesarios están concedidos y No Molestar
  /// no está interfiriendo. Útil para el semáforo de la pantalla de diagnóstico.
  bool get todoCorrecto =>
      alarmasExactas &&
      notificaciones &&
      exencionBateria &&
      fullScreenIntent &&
      !noMolestar;

  /// Resumen en texto plano para incluir en el reporte compartible.
  String get resumenTexto {
    String si(bool v) => v ? 'SÍ' : 'NO ⚠';
    return 'Alarmas exactas: ${si(alarmasExactas)}\n'
        'Notificaciones: ${si(notificaciones)}\n'
        'Exención de batería: ${si(exencionBateria)}\n'
        'Pantalla completa (lockscreen): ${si(fullScreenIntent)}\n'
        'No Molestar activo: ${noMolestar ? "SÍ ⚠" : "no"}';
  }
}
