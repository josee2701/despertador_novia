import 'dart:async';

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

  /// Inicializa el presenter: carga alarmas, inicia timers y verifica permisos.
  Future<void> iniciar() async {
    await _alarmService.init();
    await _cargarAlarmas();
    await _verificarPermisoAlarmasExactas();
    await _verificarModoNoMolestar();
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
    for (final configuracion in conjunto.alarms) {
      if (_prevAlarmSet.containsId(configuracion.id)) continue;

      final alarma = _alarmas.where((a) => a.id == configuracion.id).firstOrNull
          ?? _alarmaDesdeConfig(configuracion);

      _alarmaSonando = alarma;
      _alertaEnPantalla = true;
      alarma.pospuesta = false;
      _guardarAlarmas();

      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle == AppLifecycleState.resumed) {
        _view.onAlarmaSonandoEnForeground(alarma);
      } else {
        _view.onMostrarPantallaAlarma(alarma);
      }
    }
    _prevAlarmSet = conjunto;
  }

  /// Crea una Alarma temporal desde AlarmSettings (caso edge).
  Alarma _alarmaDesdeConfig(AlarmSettings config) {
    return Alarma(
      id: config.id,
      hora: config.dateTime,
      etiqueta: config.notificationSettings.body,
    );
  }

  /// Verifica el permiso de alarmas exactas en Android.
  Future<void> _verificarPermisoAlarmasExactas() async {
    final concedido = await _permissionService.verificarPermisoAlarmasExactas();
    _view.onPermisoNecesario(!concedido);
  }

  /// Solicita el permiso de alarmas exactas.
  Future<void> solicitarPermisoAlarmasExactas() async {
    await _permissionService.solicitarPermisoAlarmasExactas();
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
    // Solo muestra la pantalla si aún no hay una ruta de alarma apilada.
    if (_alarmaSonando != null && !_alertaEnPantalla) {
      _alertaEnPantalla = true;
      _view.onMostrarPantallaAlarma(_alarmaSonando!);
    }
  }

  /// Carga las alarmas desde almacenamiento persistente.
  ///
  /// Si encuentra alarmas vencidas (incluyendo snoozes expirados), recalcula
  /// su próxima fecha de disparo usando horaDelDia/minutoDelDia.
  Future<void> _cargarAlarmas() async {
    final resultado = await _storageService.cargarAlarmas();
    _alarmas = resultado.alarmas;
    _nextId = resultado.nextId;

    final ahora = DateTime.now();
    var huboCambios = false;

    for (final alarma in _alarmas) {
      if (alarma.activa && alarma.hora.isBefore(ahora)) {
        alarma.hora = proximaFecha(alarma.horaDelDia, alarma.minutoDelDia, alarma.diasSemana);
        alarma.pospuesta = false;
        huboCambios = true;
      }

      if (alarma.activa && alarma.hora.isAfter(ahora)) {
        await _alarmService.programar(alarma);
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
    _alarmas.add(nuevaAlarma);
    await _guardarAlarmas();
    _view.onAlarmaAgregada();
  }

  /// Activa o desactiva una alarma existente.
  Future<void> toggleAlarma(Alarma alarma, bool activa) async {
    if (activa) {
      await _alarmService.programar(alarma);
    } else {
      await _alarmService.detener(alarma.id);
    }
    alarma.activa = activa;
    await _guardarAlarmas();
    _view.onAlarmaActualizada();
  }

  /// Elimina una alarma del sistema y de la lista local.
  Future<void> eliminarAlarma(Alarma alarma) async {
    await _alarmService.detener(alarma.id);
    _alarmas.remove(alarma);
    await _guardarAlarmas();
    _view.onAlarmaEliminada();
  }

  /// Restaura una alarma previamente eliminada (para undo).
  Future<void> restaurarAlarma(Alarma alarma) async {
    _alarmas.add(alarma);
    if (alarma.activa) {
      await _alarmService.programar(alarma);
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
    }
    await _guardarAlarmas();
    _view.onAlarmaActualizada();
  }

  /// Actualiza la etiqueta de una alarma y la reprograma si está activa.
  Future<void> actualizarEtiqueta(Alarma alarma, String nuevaEtiqueta) async {
    alarma.etiqueta = nuevaEtiqueta.trim().isEmpty ? 'Alarma' : nuevaEtiqueta.trim();
    if (alarma.activa) {
      await _alarmService.programar(alarma);
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
    // alarma.hora se usa para programar el snooze; horaDelDia/minutoDelDia no cambian.
    alarma.hora = DateTime.now().add(const Duration(minutes: 5));
    alarma.pospuesta = true;
    await _alarmService.programar(alarma);
    await _guardarAlarmas();
    _alarmaSonando = null;
    _alertaEnPantalla = false;
    _view.onAlarmaActualizada();
  }

  /// Detener completamente una alarma (sin reprogramar si no es recurrente).
  Future<void> detenerAlarma(Alarma alarma) async {
    await _alarmService.detener(alarma.id);
    alarma.pospuesta = false;

    if (alarma.diasSemana.isNotEmpty) {
      // Usar horaDelDia/minutoDelDia: alarma.hora puede contener la hora del snooze.
      alarma.hora = proximaFecha(alarma.horaDelDia, alarma.minutoDelDia, alarma.diasSemana);
      await _alarmService.programar(alarma);
    }

    await _guardarAlarmas();
    _alarmaSonando = null;
    _alertaEnPantalla = false;
    _view.onAlarmaActualizada();
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
