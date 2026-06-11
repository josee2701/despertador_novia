import 'dart:async';
import 'dart:io';

import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/material.dart';

import '../models/alarma.dart';
import '../services/alarm_service.dart';
import '../services/permission_service.dart';
import '../services/storage_service.dart';
import '../utils/date_utils.dart';

/// Interfaz que define cómo el Presenter notifica cambios a la View.
///
/// La View implementa esta interfaz y el Presenter llama a estos métodos
/// cuando el estado de los datos cambia, manteniendo el patrón MVP.
abstract class AlarmasView {
  void onAlarmasCargadas();
  void onAlarmaAgregada();
  void onAlarmaActualizada();
  void onAlarmaEliminada();
  void onPermisoNecesario(bool necesita);
  void onModoNoMolestarCambiado(bool activo);
  void onMostrarPantallaAlarma(Alarma alarma);
  void onAlarmaSonandoEnForeground(Alarma alarma);
  BuildContext getContext();
}

/// Presenter del patrón MVP para la pantalla de alarmas.
///
/// Contiene toda la lógica de negocio:
/// - CRUD de alarmas (crear, leer, actualizar, eliminar)
/// - Cálculo de la próxima fecha de disparo
/// - Gestión de permisos del sistema
/// - Verificación del modo No Molestar
/// - Manejo del stream de alarmas sonando
///
/// La View solo se encarga de renderizar widgets y delegar acciones al presenter.
class AlarmasPresenter {
  AlarmasView _view;
  final AlarmService _alarmService;
  final StorageService _storageService;
  final PermissionService _permissionService;

  List<Alarma> _alarmas = [];
  int _nextId = 1;
  bool _modoNoMolestar = false;
  DateTime _ahora = DateTime.now();
  Timer? _timer;
  StreamSubscription? _suscripcionRinging;
  AlarmSet _prevAlarmSet = AlarmSet.empty();
  Alarma? _alarmaSonando;
   // Previene que onAppResumed apile múltiples rutas mientras la alarma sigue sonando.
  bool _alertaEnPantalla = false;

  /// IDs de alarmas que estamos deteniendo por acción del usuario.
  /// Evita que el cleanup del _onAlarmaSonando interfiera con
  /// cerrarConConfirmacion / detenerAlarma / posponerAlarma.
  final Set<int> _idsEnDetencion = {};

  AlarmasPresenter({
    required AlarmasView view,
    AlarmService? alarmService,
    StorageService? storageService,
    PermissionService? permissionService,
  })  : _view = view,
        _alarmService = alarmService ?? AlarmService(),
        _storageService = storageService ?? StorageService(),
        _permissionService = permissionService ?? PermissionService();

  /// Lista inmutable de alarmas actuales.
  List<Alarma> get alarmas => List.unmodifiable(_alarmas);

  /// Hora actual del sistema (se actualiza cada segundo).
  DateTime get ahora => _ahora;

  /// Indica si el modo No Molestar está activo.
  bool get modoNoMolestar => _modoNoMolestar;

  /// True si hay una alarma sonando activamente.
  bool get hayAlarmaSonando => _alarmaSonando != null;

  /// Inicializa el presenter: carga alarmas, inicia timers y verifica permisos.
  Future<void> iniciar() async {
    await _alarmService.init();
    await _cargarAlarmas();
    await _verificarPermisoAlarmasExactas();
    await _verificarPermisoNotificaciones();
    await _verificarModoNoMolestar();
    // Solicitar exención de batería si no está concedida (mejora fiabilidad en Android)
    final exentoBateria = await _permissionService.verificarExencionBateria();
    if (!exentoBateria) {
      await _permissionService.solicitarExencionBateria();
    }
    _iniciarTimer();
    _iniciarEscuchaRinging();
  }

  /// Configura la vista asociada (útil si la vista cambia).
  set view(AlarmasView v) => _view = v;

  /// Actualiza la hora actual y notifica a la vista.
  void _tick() {
    _ahora = DateTime.now();
    _view.onAlarmasCargadas();
  }

  /// Inicia un timer que actualiza la hora cada segundo.
  void _iniciarTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  /// Escucha el stream de alarmas sonando y muestra la pantalla de alarma.
  void _iniciarEscuchaRinging() {
    _suscripcionRinging = _alarmService.ringingStream.listen(_onAlarmaSonando);
  }

  /// Maneja el evento cuando una alarma comienza a sonar.
  void _onAlarmaSonando(AlarmSet conjunto) {
    // Detectar si la alarma activa desapareció del stream (detenida externamente,
    // por ejemplo deslizando la notificación o por intervención del OS).
    // Se ignora si la alarma está en nuestro set de detenciones en curso,
    // ya que la estamos gestionando nosotros.
    if (_alarmaSonando != null &&
        _prevAlarmSet.containsId(_alarmaSonando!.id) &&
        !conjunto.containsId(_alarmaSonando!.id) &&
        !_idsEnDetencion.contains(_alarmaSonando!.id)) {
      unawaited(_limpiarAlarmaSonandoExterna(_alarmaSonando!));
    }

    // Procesar alarmas que empezaron a sonar desde el último evento.
    for (final configuracion in conjunto.alarms) {
      if (_prevAlarmSet.containsId(configuracion.id)) continue;

      // Filtrar recordatorios: son silenciosos y no deben mostrar pantalla de alarma.
      // El package los detiene automáticamente (loopAudio: false); solo los limpiamos.
      if (AlarmService.esIdRecordatorio(configuracion.id)) {
        unawaited(_alarmService.detener(configuracion.id));
        continue;
      }

      final alarma = _alarmas.where((a) => a.id == configuracion.id).firstOrNull
          ?? _alarmaDesdeConfig(configuracion);

      _alarmaSonando = alarma;
      alarma.pospuesta = false;
      _guardarAlarmas();

      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle == AppLifecycleState.resumed && !_alertaEnPantalla) {
        // App visible: mostrar banner no intrusivo; el fullscreen es para cuando
        // el teléfono estaba bloqueado (lo maneja onAppResumed).
        _view.onAlarmaSonandoEnForeground(alarma);
      }
      // App en segundo plano: NO hacer push de ruta ahora.
      // onAppResumed verificará con alarmIsRinging si sigue sonando antes de mostrarla,
      // evitando que una ruta quede apilada si el usuario ya detuvo desde la notificación.
    }
    _prevAlarmSet = conjunto;
  }

  /// Limpia el estado cuando la alarma se detuvo fuera del control de la app
  /// (OS, notificación del sistema, etc.) y reprograma si es recurrente.
  Future<void> _limpiarAlarmaSonandoExterna(Alarma alarma) async {
    alarma.pospuesta = false;
    alarma.confirmacionPendiente = false;
    _alarmaSonando = null;
    _alertaEnPantalla = false;

    // Cancelar el recordatorio del ciclo actual en cualquier caso.
    await _alarmService.cancelarRecordatorio(alarma.id);

    if (alarma.diasSemana.isNotEmpty) {
      alarma.hora = proximaFecha(alarma.horaDelDia, alarma.minutoDelDia, alarma.diasSemana);
      await _alarmService.programar(alarma);
      // Programar recordatorio para el próximo disparo recurrente.
      await _alarmService.programarRecordatorio(alarma);
    } else {
      alarma.activa = false;
    }

    await _guardarAlarmas();
    _view.onAlarmaActualizada();
  }

  /// Crea una Alarma temporal desde AlarmSettings (caso edge).
  Alarma _alarmaDesdeConfig(AlarmSettings config) {
    return Alarma(
      id: config.id,
      hora: config.dateTime,
      etiqueta: 'Alarma',
    );
  }

  /// Verifica el permiso de alarmas exactas en Android.
  Future<void> _verificarPermisoAlarmasExactas() async {
    final concedido = await _permissionService.verificarPermisoAlarmasExactas();
    _view.onPermisoNecesario(!concedido);
  }

  /// Verifica el permiso de notificaciones en Android 13+.
  Future<void> _verificarPermisoNotificaciones() async {
    final concedido = await _permissionService.verificarPermisoNotificaciones();
    if (!concedido && Platform.isAndroid) {
      await _permissionService.solicitarPermisoNotificaciones();
    }
  }

  /// Solicita el permiso de alarmas exactas.
  Future<void> solicitarPermisoAlarmasExactas() async {
    await _permissionService.verificarYSolicitarPermisoAlarmasExactas();
    final concedido = await _permissionService.verificarPermisoAlarmasExactas();
    _view.onPermisoNecesario(!concedido);
  }

  /// Verifica el estado del modo No Molestar.
  Future<void> _verificarModoNoMolestar() async {
    final activo = await _permissionService.verificarModoNoMolestar();
    if (activo != _modoNoMolestar) {
      _modoNoMolestar = activo;
      _view.onModoNoMolestarCambiado(activo);
    }
  }

  /// Maneja el evento de ciclo de vida cuando la app vuelve a primer plano.
  Future<void> onAppResumed() async {
    await _verificarModoNoMolestar();

    // Si _alarmaSonando no se asignó aún (race condition con el stream),
    // buscar activamente si alguna alarma está sonando.
    if (_alarmaSonando == null) {
      for (final alarma in _alarmas) {
        if (alarma.activa && await _alarmService.alarmIsRinging(alarma.id)) {
          _alarmaSonando = alarma;
          break;
        }
      }
    }

    if (_alarmaSonando == null) return;

    final sigueSonando = await _alarmService.alarmIsRinging(_alarmaSonando!.id);

    if (!sigueSonando) {
      // Detenida externamente — limpiar estado y reprogramar si es recurrente.
      final alarma = _alarmaSonando!;
      _alarmaSonando = null;
      _alertaEnPantalla = false;
      alarma.pospuesta = false;
      alarma.confirmacionPendiente = false;

      // Cancelar el recordatorio del ciclo actual.
      await _alarmService.cancelarRecordatorio(alarma.id);

      if (alarma.diasSemana.isNotEmpty) {
        alarma.hora = proximaFecha(alarma.horaDelDia, alarma.minutoDelDia, alarma.diasSemana);
        await _alarmService.programar(alarma);
        // Programar recordatorio para el próximo disparo recurrente.
        await _alarmService.programarRecordatorio(alarma);
      } else {
        alarma.activa = false; // una sola vez: desactivar si se paró desde la notificación
      }

      await _guardarAlarmas();
      _view.onAlarmaActualizada();
      return;
    }

    // Sigue sonando — mostrar pantalla solo si no hay una ruta ya apilada.
    if (!_alertaEnPantalla) {
      _alertaEnPantalla = true;
      _view.onMostrarPantallaAlarma(_alarmaSonando!);
    }
  }

  /// Carga las alarmas desde almacenamiento persistente.
  ///
  /// Si encuentra alarmas vencidas (incluyendo snoozes expirados), recalcula
  /// su próxima fecha de disparo usando horaDelDia/minutoDelDia.
  /// Limpia alarmas nativas huérfanas que no están en SharedPreferences.
  Future<void> _cargarAlarmas() async {
    final resultado = await _storageService.cargarAlarmas();
    _alarmas = resultado.alarmas;
    _nextId = resultado.nextId;

    // Limpiar alarmas nativas huérfanas (no están en nuestra lista activa).
    // Se excluyen los recordatorios (id > offsetRecordatorio): se gestionan
    // por separado y se reprograman más abajo junto con sus alarmas.
    final idsActivas = _alarmas.where((a) => a.activa).map((a) => a.id).toSet();
    final alarmasNativas = await _alarmService.getAlarmasNativas();
    for (final nativa in alarmasNativas) {
      if (AlarmService.esIdRecordatorio(nativa.id)) continue;
      if (!idsActivas.contains(nativa.id)) {
        await _alarmService.detener(nativa.id);
      }
    }

    final ahora = DateTime.now();
    var huboCambios = false;

    for (final alarma in _alarmas) {
      if (alarma.activa && alarma.hora.isBefore(ahora)) {
        // Limpiar confirmación vencida independientemente del tipo
        alarma.confirmacionPendiente = false; // ← NUEVO
        if (alarma.diasSemana.isEmpty) {
          alarma.activa = false;
        } else {
          alarma.hora = proximaFecha(alarma.horaDelDia, alarma.minutoDelDia, alarma.diasSemana);
        }
        alarma.pospuesta = false;
        huboCambios = true;
      }

      if (alarma.activa && alarma.hora.isAfter(ahora)) {
        await _alarmService.programar(alarma);
        // Reprogramar recordatorio si quedan más de 30 minutos.
        await _alarmService.programarRecordatorio(alarma);
      }
    }

    if (huboCambios) await _guardarAlarmas();
    _view.onAlarmasCargadas();
  }

  /// Persiste la lista actual de alarmas en almacenamiento local.
  Future<void> _guardarAlarmas() async {
    await _storageService.guardarAlarmas(_alarmas, _nextId);
  }

  /// Agrega una nueva alarma con los parámetros proporcionados.
  Future<void> agregarAlarma({
    required int hora,
    required int minuto,
    required String etiqueta,
    required List<int> diasSemana,
  }) async {
    final nuevaAlarma = Alarma(
      id: _nextId++,
      hora: proximaFecha(hora, minuto, diasSemana),
      etiqueta: etiqueta.trim().isEmpty ? 'Alarma' : etiqueta.trim(),
      diasSemana: diasSemana,
    );

    await _alarmService.programar(nuevaAlarma);
    await _alarmService.programarRecordatorio(nuevaAlarma);
    _alarmas.add(nuevaAlarma);
    await _guardarAlarmas();
    _view.onAlarmaAgregada();
  }

  /// Activa o desactiva una alarma existente.
  Future<void> toggleAlarma(Alarma alarma, bool activa) async {
    if (activa) {
      alarma.hora = proximaFecha(alarma.horaDelDia, alarma.minutoDelDia, alarma.diasSemana);
      alarma.pospuesta = false;
      await _alarmService.programar(alarma);
      await _alarmService.programarRecordatorio(alarma);
    } else {
      await _alarmService.detener(alarma.id);
      await _alarmService.cancelarRecordatorio(alarma.id);
    }
    alarma.activa = activa;
    await _guardarAlarmas();
    _view.onAlarmaActualizada();
  }

  /// Elimina una alarma del sistema y de la lista local.
  Future<void> eliminarAlarma(Alarma alarma) async {
    await _alarmService.detener(alarma.id);
    await _alarmService.cancelarRecordatorio(alarma.id);
    _alarmas.remove(alarma);
    await _guardarAlarmas();
    _view.onAlarmaEliminada();
  }

  /// Restaura una alarma previamente eliminada (para undo).
  Future<void> restaurarAlarma(Alarma alarma) async {
    _alarmas.add(alarma);
    if (alarma.activa) {
      alarma.hora = proximaFecha(alarma.horaDelDia, alarma.minutoDelDia, alarma.diasSemana);
      alarma.pospuesta = false;
      await _alarmService.programar(alarma);
      await _alarmService.programarRecordatorio(alarma);
    }
    await _guardarAlarmas();
    _view.onAlarmaAgregada();
  }

  /// Actualiza la hora de una alarma y la reprograma.
  Future<void> actualizarHora(Alarma alarma, int nuevaHora, int nuevoMinuto) async {
    alarma.horaDelDia = nuevaHora;
    alarma.minutoDelDia = nuevoMinuto;
    // proximaFecha respeta los días de repetición, evitando que la alarma
    // caiga en un día no seleccionado.
    alarma.hora = proximaFecha(nuevaHora, nuevoMinuto, alarma.diasSemana);
    if (alarma.activa) {
      await _alarmService.programar(alarma);
      // Cancelar el recordatorio anterior y programar uno con la nueva hora.
      await _alarmService.cancelarRecordatorio(alarma.id);
      await _alarmService.programarRecordatorio(alarma);
    }
    await _guardarAlarmas();
    _view.onAlarmaActualizada();
  }

  /// Actualiza la etiqueta de una alarma y la reprograma si está activa.
  Future<void> actualizarEtiqueta(Alarma alarma, String nuevaEtiqueta) async {
    alarma.etiqueta = nuevaEtiqueta.trim().isEmpty ? 'Alarma' : nuevaEtiqueta.trim();
    if (alarma.activa) {
      await _alarmService.programar(alarma);
      // Reprogramar el recordatorio para que muestre la etiqueta actualizada.
      await _alarmService.cancelarRecordatorio(alarma.id);
      await _alarmService.programarRecordatorio(alarma);
    }
    await _guardarAlarmas();
    _view.onAlarmaActualizada();
  }

  /// Actualiza los días de repetición de una alarma y la reprograma.
  Future<void> actualizarDiasSemana(Alarma alarma, List<int> nuevosDias) async {
    alarma.diasSemana = nuevosDias;

    if (alarma.activa) {
      alarma.hora = proximaFecha(alarma.horaDelDia, alarma.minutoDelDia, nuevosDias);
      await _alarmService.programar(alarma);
      // Actualizar el recordatorio con la nueva próxima fecha de disparo.
      await _alarmService.cancelarRecordatorio(alarma.id);
      await _alarmService.programarRecordatorio(alarma);
    }

    await _guardarAlarmas();
    _view.onAlarmaActualizada();
  }

  /// Actualiza todos los campos de una alarma de una vez.
  Future<void> actualizarAlarmaCompleta({
    required Alarma alarma,
    int? nuevaHora,
    int? nuevoMinuto,
    String? nuevaEtiqueta,
    List<int>? nuevosDias,
  }) async {
    if (nuevaHora != null && nuevoMinuto != null) {
      alarma.horaDelDia = nuevaHora;
      alarma.minutoDelDia = nuevoMinuto;
    }

    if (nuevaEtiqueta != null) {
      alarma.etiqueta = nuevaEtiqueta.trim().isEmpty ? 'Alarma' : nuevaEtiqueta.trim();
    }

    if (nuevosDias != null) {
      alarma.diasSemana = nuevosDias;
    }

    // Recalcular próximo disparo si cambió la hora o los días.
    if ((nuevaHora != null && nuevoMinuto != null) || nuevosDias != null) {
      alarma.hora = proximaFecha(alarma.horaDelDia, alarma.minutoDelDia, alarma.diasSemana);
    }

    if (alarma.activa) {
      await _alarmService.programar(alarma);
      // Actualizar el recordatorio si cambió cualquier dato que aparece en la notificación.
      if ((nuevaHora != null && nuevoMinuto != null) || nuevosDias != null || nuevaEtiqueta != null) {
        await _alarmService.cancelarRecordatorio(alarma.id);
        await _alarmService.programarRecordatorio(alarma);
      }
    }
    await _guardarAlarmas();
    _view.onAlarmaActualizada();
  }

  /// Devuelve la próxima alarma activa ordenada por cercanía.
  Alarma? obtenerProximaAlarma() {
    final candidatas = _alarmas
        .where((a) => a.activa && a.hora.isAfter(_ahora))
        .toList()
      ..sort((a, b) => a.hora.compareTo(b.hora));

    return candidatas.isEmpty ? null : candidatas.first;
  }

  /// Devuelve el texto de la próxima alarma: "Próxima alarma: [nombre] en [tiempo]".
  String obtenerTextoProximaAlarma() {
    final proxima = obtenerProximaAlarma();
    if (proxima == null) return 'No hay alarmas programadas';

    final tiempo = textoTiempoRestante(proxima.hora, _ahora);
    if (tiempo == null) return 'No hay alarmas programadas';

    return '${proxima.etiqueta} en $tiempo';
  }

  /// Posponer una alarma activa por 5 minutos.
  Future<void> posponerAlarma(Alarma alarma) async {
    _idsEnDetencion.add(alarma.id);
    try {
      await _alarmService.detener(alarma.id);
      // Cancelar el recordatorio: el snooze tiene hora temporal y no aplica recordatorio.
      await _alarmService.cancelarRecordatorio(alarma.id);
      alarma.hora = DateTime.now().add(const Duration(minutes: 5));
      alarma.pospuesta = true;
      await _alarmService.programar(alarma);
      await _guardarAlarmas();
      _alarmaSonando = null;
      _alertaEnPantalla = false;
      _view.onAlarmaActualizada();
    } finally {
      Future.delayed(const Duration(milliseconds: 500), () {
        _idsEnDetencion.remove(alarma.id);
      });
    }
  }

  /// Detener completamente una alarma (sin reprogramar si no es recurrente).
  Future<void> detenerAlarma(Alarma alarma) async {
    _idsEnDetencion.add(alarma.id);
    try {
      await _alarmService.detener(alarma.id);
      // Cancelar siempre el recordatorio del ciclo actual.
      await _alarmService.cancelarRecordatorio(alarma.id);
      alarma.pospuesta = false;
      alarma.confirmacionPendiente = false;

      if (alarma.diasSemana.isNotEmpty) {
        // Recurrente: siempre reprogramar (con o sin confirmación).
        // Usar horaDelDia/minutoDelDia: alarma.hora puede contener la hora del snooze/confirmación.
        alarma.hora = proximaFecha(alarma.horaDelDia, alarma.minutoDelDia, alarma.diasSemana);
        await _alarmService.programar(alarma);
        // Programar recordatorio para el próximo disparo.
        await _alarmService.programarRecordatorio(alarma);
      } else {
        // Una sola vez: desactivar definitivamente.
        alarma.activa = false;
      }

      await _guardarAlarmas();
      _alarmaSonando = null;
      _alertaEnPantalla = false;
      _view.onAlarmaActualizada();
    } finally {
      Future.delayed(const Duration(milliseconds: 500), () {
        _idsEnDetencion.remove(alarma.id);
      });
    }
  }

  /// Cierra la pantalla de alarma y programa una re-activación a los 30 segundos
  /// para que el usuario confirme que está despierto.
  Future<void> cerrarConConfirmacion(Alarma alarma) async {
    _idsEnDetencion.add(alarma.id);
    try {
      // Detener el audio actual antes de reprogramar (igual que posponerAlarma).
      await _alarmService.detener(alarma.id);
      // El recordatorio ya disparó antes de que la alarma sonara (invariante: se programa
      // 30 min antes), pero se cancela defensivamente por consistencia con otros métodos.
      await _alarmService.cancelarRecordatorio(alarma.id);
      alarma.confirmacionPendiente = true;
      alarma.pospuesta = false;

      // Programar el re-sonido a los 30 segundos
      alarma.hora = DateTime.now().add(const Duration(seconds: 30));
      await _alarmService.programar(alarma);

      await _guardarAlarmas();

      // Limpiar estado de alarma sonando para que la UI vuelva a la pantalla principal
      _alarmaSonando = null;
      _alertaEnPantalla = false;
      _view.onAlarmaActualizada();
    } finally {
      Future.delayed(const Duration(milliseconds: 500), () {
        _idsEnDetencion.remove(alarma.id);
      });
    }
  }

  /// Abre la configuración del sistema.
  Future<void> abrirConfiguracion() async {
    await _permissionService.abrirConfiguracion();
  }

  /// Limpia recursos al destruir la vista.
  void dispose() {
    _timer?.cancel();
    _suscripcionRinging?.cancel();
  }
}
