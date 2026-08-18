import 'dart:async';
import 'dart:io';

import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/material.dart';

import '../models/alarma.dart';
import '../services/alarm_service.dart';
import '../services/log_service.dart';
import '../services/permission_service.dart';
import '../services/recordatorio_service.dart';
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
  void onFullScreenIntentDenegado(bool denegado);
  void onAutostartRecomendado(bool recomendado);
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
  final RecordatorioService _recordatorioService;

  List<Alarma> _alarmas = [];
  int _nextId = 1;
  bool _modoNoMolestar = false;
  DateTime _ahora = DateTime.now();

  /// Notifica cada segundo la hora actual sin reconstruir toda la pantalla.
  /// La vista escucha este notifier con un [ValueListenableBuilder] que solo
  /// envuelve el texto de "Próxima alarma", evitando ~60 rebuilds/min del
  /// header, la lista de tarjetas y el banner.
  final ValueNotifier<DateTime> ahoraNotifier = ValueNotifier(DateTime.now());

  Timer? _timer;
  bool _disposed = false;
  StreamSubscription? _suscripcionRinging;
  AlarmSet _prevAlarmSet = AlarmSet.empty();
  Alarma? _alarmaSonando;
  /// Momento en que la alarma actual empezó a sonar. Se usa para registrar
  /// cuántos segundos sonó antes de detenerse (distingue "se apaga al instante"
  /// — sospecha de audio — de "kill del OS" a los 20-40s en MIUI).
  DateTime? _inicioSonando;
   // Previene que onAppResumed apile múltiples rutas mientras la alarma sigue sonando.
  bool _alertaEnPantalla = false;

  /// IDs que el sistema reportaba SONANDO en el momento de cargar las alarmas,
  /// es decir, antes de que la app tuviera estado alguno.
  ///
  /// Distingue los dos orígenes posibles de un evento de `Alarm.ringing`:
  /// - La app se abrió POR la alarma (full-screen intent con el proceso
  ///   muerto). `Alarm.init()` → `checkAlarm()` siembra el BehaviorSubject de
  ///   `ringing` con esa alarma ANTES de que [_iniciarEscuchaRinging] se
  ///   suscriba, así que el primer evento que recibimos ya la trae y el ciclo
  ///   de vida está en `resumed` (la Activity acaba de abrirse). Sin esta
  ///   distinción se tomaba la rama del banner: la persona se despertaba con
  ///   un aviso pequeño en la pantalla principal en vez de
  ///   `PantallaAlarmaActiva` y su deslizamiento anti-remoloneo.
  /// - La alarma empezó a sonar con la app ya en uso → banner, que es lo
  ///   correcto ahí: la persona está mirando la pantalla.
  ///
  /// Se rellena en [_cargarAlarmas] con la consulta real al sistema
  /// (`alarmIsRinging`), la misma fuente que usa `checkAlarm()`, y cada ID se
  /// consume al atenderlo: un disparo posterior de esa misma alarma (p. ej. la
  /// confirmación de despertar) ya ocurre con la app en uso.
  final Set<int> _idsSonandoAlArrancar = {};

  /// IDs de alarmas que estamos deteniendo por acción del usuario.
  /// Evita que el cleanup del _onAlarmaSonando interfiera con
  /// cerrarConConfirmacion / detenerAlarma / posponerAlarma.
  final Set<int> _idsEnDetencion = {};

  /// True cuando [iniciar] terminó por completo.
  ///
  /// `iniciar()` abre diálogos del sistema (notificaciones, exención de
  /// batería). Al cerrarlos llega `resumed` y la vista llama a [onAppResumed]
  /// EN PARALELO con el resto de `iniciar()`, antes de que la escucha de
  /// `Alarm.ringing` exista. Auditar y normalizar sobre ese estado a medio
  /// construir puede cancelar como huérfana una alarma que está sonando.
  bool _iniciado = false;

  /// Guardia de reentrada de [onAppResumed]: dos `resumed` encadenados no
  /// deben auditar a la vez sobre la misma lista.
  bool _procesandoResume = false;

  /// True cuando llegó un `resumed` que aún no se ha podido procesar porque
  /// [iniciar] seguía en vuelo. Ver [resumePendiente].
  bool _resumePendiente = false;

  /// True mientras haya un `resumed` recibido pero todavía sin procesar.
  ///
  /// La vista lo consulta en el `.then()` que encadena a [onAppResumed]: hasta
  /// que el resume se procese, [hayAlarmaSonando] no significa nada (nadie ha
  /// consultado aún `alarmIsRinging`), así que decidir con ese valor podría
  /// mostrar el anuncio de apertura ENCIMA de una alarma sonando.
  bool get resumePendiente => _resumePendiente;

  /// Desplazamiento con el que las versiones ANTIGUAS de la app programaban el
  /// aviso de "suena en 30 minutos" como ALARMA nativa (`Alarm.set`).
  ///
  /// Coincide en valor con [RecordatorioService.offsetNotificacion], pero es
  /// una cosa distinta: aquel identifica notificaciones locales del
  /// planificador y este identifica alarmas nativas heredadas que hay que
  /// purgar. No los unifiques: si algún día cambia el offset de las
  /// notificaciones, el de las alarmas heredadas debe seguir siendo 10000
  /// para poder limpiar las instalaciones antiguas.
  static const int offsetAlarmaRecordatorioHeredado = 10000;

  /// Tiempo tras el cual la alarma vuelve a sonar cuando el usuario cierra la
  /// pantalla con "confirmación de despertar", para asegurar que despertó.
  static const Duration duracionConfirmacion = Duration(seconds: 30);

  AlarmasPresenter({
    required AlarmasView view,
    AlarmService? alarmService,
    StorageService? storageService,
    PermissionService? permissionService,
    RecordatorioService? recordatorioService,
    void Function(String evento)? registro,
  })  : _view = view,
        _alarmService = alarmService ?? AlarmService(),
        _storageService = storageService ?? StorageService(),
        _permissionService = permissionService ?? PermissionService(),
        _recordatorioService = recordatorioService ?? RecordatorioService(),
        _registro = registro ??
            ((evento) => unawaited(LogService.instancia.registrar(evento)));

  /// Sumidero del log de diagnóstico. Inyectable para poder verificar en las
  /// pruebas que cada evento (suena, se detiene, se edita…) queda registrado.
  final void Function(String evento) _registro;

  /// Lista inmutable de alarmas actuales.
  List<Alarma> get alarmas => List.unmodifiable(_alarmas);

  /// Hora actual del sistema (se actualiza cada segundo).
  DateTime get ahora => _ahora;

  /// Indica si el modo No Molestar está activo.
  bool get modoNoMolestar => _modoNoMolestar;

  /// True si hay una alarma sonando activamente.
  bool get hayAlarmaSonando => _alarmaSonando != null;

  /// La alarma que suena ahora mismo, o null. Es siempre la misma que la vista
  /// tiene en pantalla (banner o `PantallaAlarmaActiva`).
  Alarma? get alarmaSonando => _alarmaSonando;

  /// Atajo para registrar un evento en el log de diagnóstico.
  void _log(String evento) => _registro(evento);

  /// Inicializa el presenter: carga alarmas, inicia timers y verifica permisos.
  ///
  /// El bloque de carga/permisos/diagnóstico está envuelto en un `try/catch`
  /// a propósito: si cualquiera de esas comprobaciones lanza algo que no sea
  /// [PlatformException] (la única excepción que los servicios ya atrapan),
  /// [_iniciarTimer] y [_iniciarEscuchaRinging] deben ejecutarse igual. Sin
  /// esto, un fallo ahí abortaría `iniciar()` a mitad y la app se quedaría sin
  /// reloj y, sobre todo, sin la suscripción a `Alarm.ringing`: ninguna
  /// alarma volvería a mostrar su pantalla en toda la sesión. La vista solo
  /// hace `debugPrint` en su `catchError`, así que este es el único lugar que
  /// puede evitarlo.
  Future<void> iniciar() async {
    _log('App abierta');
    // `init()` es lo más propenso a lanzar de todo el método (canal de
    // plataforma + DataStore). Va en su propio try: si falla, el resto —y
    // sobre todo el reloj y la escucha de Alarm.ringing— tienen que arrancar
    // igual, que es justo lo que este método promete.
    try {
      await _alarmService.init();
      await _purgarRecordatoriosHeredados();
    } catch (e) {
      _log('⚠ ERROR al inicializar el package de alarmas: $e — la app '
          'continúa, pero programar o detener alarmas puede fallar');
    }
    try {
      await _detectarReinicio();
      await _cargarAlarmas();
      await _verificarPermisoAlarmasExactas();
      await _verificarPermisoNotificaciones();
      await _verificarModoNoMolestar();
      // Solicitar exención de batería si no está concedida (mejora fiabilidad en Android)
      final exentoBateria = await _permissionService.verificarExencionBateria();
      if (!exentoBateria) {
        await _permissionService.solicitarExencionBateria();
      }
      // Registrar instantánea de permisos: clave para diagnosticar fallos en MIUI/Xiaomi.
      final estado = await _permissionService.obtenerEstadoPermisos();
      _log('Dispositivo: ${await _permissionService.descripcionDispositivo()}');
      _log('Permisos → exactas:${estado.alarmasExactas} '
          'notif:${estado.notificaciones} '
          'bateria:${estado.exencionBateria} '
          'pantallaCompleta:${estado.fullScreenIntent} '
          'noMolestar:${estado.noMolestar}');
      // Avisar a la vista si no puede mostrar la alarma sobre el lockscreen:
      // causa #1 de "no aparece la pantalla con el teléfono bloqueado" en Android 14+/MIUI.
      _view.onFullScreenIntentDenegado(!estado.fullScreenIntent);
      await _verificarAutostart();
    } catch (e) {
      _log('⚠ ERROR durante el arranque: $e — la app continúa con el reloj '
          'y la escucha de alarmas');
    }
    _iniciarTimer();
    _iniciarEscuchaRinging();
    _iniciado = true;
    // Un `resumed` que llegó mientras esto seguía en vuelo NO se descarta: se
    // difiere hasta aquí, con la lista cargada y la escucha de `Alarm.ringing`
    // ya montada, que es justo lo que le faltaba.
    if (_resumePendiente) {
      _resumePendiente = false;
      _log('Resume diferido: se procesa ahora que iniciar() ha terminado');
      await onAppResumed();
    }
  }

  /// Cancela las alarmas nativas que las versiones antiguas de la app crearon
  /// para el aviso de "suena en 30 minutos" (`Alarm.set` con el ID desplazado).
  ///
  /// Se ejecuta justo después de `Alarm.init()`, ANTES de cualquier otra cosa,
  /// y no dentro de [_cargarAlarmas]: al actualizar la app, `ArranqueReceiver`
  /// puede haber rearmado uno de esos recordatorios con el `AlarmStorage` que
  /// dejó la versión vieja. Si dispara, deja vivo el foreground service y el
  /// `ringingAlarmIds` del package ocupado, y la alarma real de la mañana se
  /// descarta — el bug original, una última noche. Purgar aquí cierra la
  /// ventana que va desde la actualización hasta la primera apertura.
  Future<void> _purgarRecordatoriosHeredados() async {
    final nativas = await _alarmService.getAlarmasNativas();
    for (final nativa in nativas) {
      if (nativa.id <= offsetAlarmaRecordatorioHeredado) continue;
      try {
        await _alarmService.detener(nativa.id);
        _log('Recordatorio heredado #${nativa.id} purgado: los avisos de '
            '30 min ya no se programan como alarmas');
      } catch (e) {
        _log('⚠ ERROR al purgar el recordatorio heredado #${nativa.id}: $e');
      }
    }
  }

  /// Abre el ajuste del sistema para conceder el full-screen intent.
  Future<void> abrirAjustesFullScreenIntent() async {
    await _permissionService.abrirAjustesFullScreenIntent();
  }

  /// Avisa a la vista si conviene enseñar la guía de Inicio automático.
  ///
  /// Solo en fabricantes que matan apps de forma agresiva (Xiaomi, Huawei…) y
  /// solo mientras el usuario no la haya atendido.
  Future<void> _verificarAutostart() async {
    final agresivo = await _permissionService.esFabricanteAgresivo();
    final atendido = await _storageService.cargarAutostartAtendido();
    final recomendado = agresivo && !atendido;
    if (recomendado) {
      _log('Fabricante agresivo detectado: se recomienda activar el '
          'Inicio automático');
    }
    _view.onAutostartRecomendado(recomendado);
  }

  /// Abre la pantalla de Inicio automático del fabricante.
  ///
  /// El aviso solo se da por atendido si la pantalla del fabricante se abrió
  /// de verdad. Si ninguno de los componentes OEM resuelve, el usuario acaba
  /// en los ajustes genéricos de la app, donde no puede activar nada: ocultar
  /// el banner ahí eliminaría en silencio la única mitigación de la causa
  /// raíz número uno (el OEM mata el proceso y la alarma no suena).
  Future<void> abrirAutostart() async {
    final abierto = await _permissionService.abrirAutostartOEM();
    if (!abierto) {
      _log('No se pudo abrir la pantalla de Inicio automático del '
          'fabricante: el aviso sigue pendiente');
      return;
    }
    await _storageService.guardarAutostartAtendido();
    _log('Pantalla de Inicio automático abierta: aviso marcado como atendido');
    _view.onAutostartRecomendado(false);
  }

  /// Detecta si el dispositivo se reinició desde la última sesión comparando el
  /// uptime actual con el guardado. Un descenso implica reinicio: las alarmas
  /// pudieron perderse si el OEM no entregó BOOT_COMPLETED (la auditoría de
  /// [_cargarAlarmas] las reprograma). Registra el resultado para el diagnóstico.
  Future<void> _detectarReinicio() async {
    final uptimeActual = await _permissionService.tiempoEncendidoMs();
    if (uptimeActual == null) return;
    final uptimeAnterior = await _storageService.cargarUptime();
    String formato(int ms) {
      final h = ms ~/ 3600000;
      final m = (ms % 3600000) ~/ 60000;
      return '${h}h ${m}min';
    }
    if (uptimeAnterior != null && uptimeActual < uptimeAnterior) {
      _log('⚠ REINICIO del dispositivo detectado desde la última sesión '
          '(uptime ${formato(uptimeActual)} < ${formato(uptimeAnterior)}). '
          'Verificando alarmas programadas…');
    } else {
      _log('Sesión: uptime del dispositivo ${formato(uptimeActual)}');
    }
    await _storageService.guardarUptime(uptimeActual);
  }

  /// Configura la vista asociada (útil si la vista cambia).
  set view(AlarmasView v) => _view = v;

  /// Actualiza la hora actual y la publica en [ahoraNotifier].
  ///
  /// Ya NO llama a `_view.onAlarmasCargadas()`: el reloj de "Próxima alarma"
  /// se refresca vía [ahoraNotifier] (solo reconstruye ese texto), evitando
  /// reconstruir toda la pantalla cada segundo.
  void _tick() {
    _ahora = DateTime.now();
    ahoraNotifier.value = _ahora;
  }

  /// Inicia un timer que actualiza la hora cada segundo.
  ///
  /// Cancela cualquier timer previo: `iniciar()` espera diálogos de permisos y
  /// el resume de esos diálogos puede haber creado ya un timer vía
  /// [reanudarTimer]. Sin este cancel, el anterior quedaría huérfano y seguiría
  /// escribiendo en [ahoraNotifier] después del `dispose()`.
  void _iniciarTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  /// True si el timer de reloj está activo. Expuesto para pruebas.
  bool get timerActivo => _timer?.isActive ?? false;

  /// Pausa el timer del reloj (p. ej. al pasar la app a segundo plano).
  /// Evita trabajo innecesario cuando la pantalla no es visible.
  void pausarTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Reanuda el timer del reloj (p. ej. al volver a primer plano).
  ///
  /// Hace un [_tick] inmediato para refrescar la hora sin esperar 1s y evita
  /// crear un segundo timer si ya había uno activo.
  void reanudarTimer() {
    if (_timer == null) {
      _tick();
      _iniciarTimer();
    }
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
    //
    // Solo la PRIMERA gobierna el estado y la pantalla. Antes ganaba la última
    // del bucle, así que con dos alarmas a la vez la persona veía el aviso de
    // una mientras _alarmaSonando apuntaba a la otra: detener la de la
    // pantalla dejaba hayAlarmaSonando en true y _procesarResume consultaba a
    // la equivocada.
    Alarma? primeraNueva;
    for (final configuracion in conjunto.alarms) {
      if (_prevAlarmSet.containsId(configuracion.id)) continue;

      final alarma = _alarmas.where((a) => a.id == configuracion.id).firstOrNull
          ?? _alarmaDesdeConfig(configuracion);
      alarma.pospuesta = false;

      if (primeraNueva != null) {
        // No hay arreglo posible desde Dart: el package descarta la segunda
        // alarma en `onStartCommand` (`allowAlarmOverlap` es false por
        // defecto) y la auditoría tampoco la repone, porque su hora ya pasó y
        // solo repone las futuras. Se registra para que el patrón "alarma de
        // respaldo cinco minutos después" sea reconocible en el diagnóstico si
        // la usuaria vuelve a reportar que no sonó.
        _log('⚠ Alarma #${alarma.id} "${alarma.etiqueta}" SOLAPADA con la '
            '#${primeraNueva.id}: solo se atiende la primera. El package '
            'descarta las que se solapan, así que una alarma de respaldo a la '
            'misma hora NO suena');
        _idsSonandoAlArrancar.remove(alarma.id);
        continue;
      }
      primeraNueva = alarma;

      _alarmaSonando = alarma;
      _inicioSonando = DateTime.now();

      final lifecycle = WidgetsBinding.instance.lifecycleState;
      final tipoDisparo = alarma.confirmacionPendiente
          ? 'RE-SONÓ (confirmación de despertar a los 30s)'
          : 'DISPARÓ';
      // Se consume la marca: un disparo posterior de esta misma alarma ya
      // ocurre con la app en uso, no en un arranque provocado por ella.
      final yaSonabaAlArrancar = _idsSonandoAlArrancar.remove(alarma.id);
      _log('Alarma #${alarma.id} "${alarma.etiqueta}" $tipoDisparo '
          '(app: ${lifecycle == AppLifecycleState.resumed ? "visible" : "segundo plano/bloqueada"}'
          '${yaSonabaAlArrancar ? ", abierta POR la alarma" : ""})');
      if (yaSonabaAlArrancar && !_alertaEnPantalla) {
        // La alarma ya sonaba antes de que la app existiera: el full-screen
        // intent abrió la Activity POR ella. Aunque el ciclo de vida diga
        // "resumed", la persona está dormida y no ha tocado nada, así que le
        // toca la pantalla completa con el deslizamiento anti-remoloneo, no un
        // banner que se ignora medio dormida.
        _alertaEnPantalla = true;
        _view.onMostrarPantallaAlarma(alarma);
      } else if (lifecycle == AppLifecycleState.resumed && !_alertaEnPantalla) {
        // App visible y en uso: mostrar banner no intrusivo; el fullscreen es
        // para cuando el teléfono estaba bloqueado (lo maneja onAppResumed).
        _alertaEnPantalla = true;
        _view.onAlarmaSonandoEnForeground(alarma);
      }
      // App en segundo plano: NO hacer push de ruta ahora.
      // onAppResumed verificará con alarmIsRinging si sigue sonando antes de mostrarla,
      // evitando que una ruta quede apilada si el usuario ya detuvo desde la notificación.
    }
    // Un solo guardado por evento, con `pospuesta` ya limpio en todas.
    if (primeraNueva != null) _guardarAlarmas();
    _prevAlarmSet = conjunto;
  }

  /// Limpia el estado cuando la alarma se detuvo fuera del control de la app
  /// (OS, notificación del sistema, etc.) y reprograma si es recurrente.
  Future<void> _limpiarAlarmaSonandoExterna(Alarma alarma) async {
    final duracion = _inicioSonando == null
        ? '?'
        : '${DateTime.now().difference(_inicioSonando!).inSeconds}s';
    _log('⚠ Alarma #${alarma.id} detenida EXTERNAMENTE tras sonar $duracion '
        '(notificación, deslizada o el sistema mató la app)');
    _inicioSonando = null;
    alarma.pospuesta = false;
    alarma.confirmacionPendiente = false;
    _alarmaSonando = null;
    _alertaEnPantalla = false;

    // Cancelar el recordatorio del ciclo actual en cualquier caso.
    await _recordatorioService.cancelar(alarma.id);

    if (alarma.diasSemana.isNotEmpty) {
      alarma.hora = proximaFecha(alarma.horaDelDia, alarma.minutoDelDia, alarma.diasSemana);
      try {
        await _alarmService.programar(alarma);
        // Programar recordatorio para el próximo disparo recurrente.
        await _recordatorioService.programar(alarma);
      } catch (e) {
        // Este método se invoca con `unawaited` desde el stream de ringing:
        // sin este catch la excepción quedaría como error asíncrono suelto y
        // la alarma ni siquiera se guardaría con su nueva hora.
        _log('⚠ ERROR al reprogramar la alarma #${alarma.id} tras detenerse '
            'externamente: $e');
      }
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
      _log('Modo No Molestar ${activo ? "ACTIVADO — las alarmas podrían no sonar" : "desactivado"}');
      _view.onModoNoMolestarCambiado(activo);
    }
  }

  /// Maneja el evento de ciclo de vida cuando la app vuelve a primer plano.
  ///
  /// Dos guardias antes de tocar nada:
  /// - [_iniciado]: los diálogos de permisos que abre [iniciar] provocan un
  ///   `resumed` mientras `iniciar()` sigue en vuelo. Auditar y normalizar
  ///   entonces trabaja sobre una lista a medio cargar y sin la escucha de
  ///   `Alarm.ringing` montada. Ese resume se DIFIERE, nunca se descarta (ver
  ///   [resumePendiente]).
  /// - [_procesandoResume]: dos `resumed` encadenados no deben auditar a la
  ///   vez sobre la misma lista.
  Future<void> onAppResumed() async {
    if (!_iniciado) {
      // Descartarlo sin más era una regresión crítica: la vista encadena un
      // `.then()` a este Future para decidir el anuncio de apertura, y ese
      // callback corría igual con `hayAlarmaSonando == false` —nadie había
      // consultado `alarmIsRinging`— pudiendo mostrar el anuncio ENCIMA de una
      // alarma sonando. Se marca como pendiente y lo procesa [iniciar] al
      // terminar; mientras tanto, [resumePendiente] le dice a la vista que
      // todavía no puede decidir nada.
      _resumePendiente = true;
      _log('Resume diferido: iniciar() todavía no ha terminado');
      return;
    }
    if (_procesandoResume) return;
    _procesandoResume = true;
    try {
      await _procesarResume();
    } catch (e) {
      // La vista encadena un `.then()` a este Future (anuncio de apertura).
      // Si la excepción escapara, ese callback no se ejecutaría nunca y el
      // error quedaría como error de Future no capturado, sin rastro.
      _log('⚠ ERROR al volver a primer plano: $e');
    } finally {
      _procesandoResume = false;
    }
  }

  /// Cuerpo real de [onAppResumed], ya con las guardias aplicadas.
  Future<void> _procesarResume() async {
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

    if (_alarmaSonando == null) {
      // Nada sonando según nuestro estado, pero puede quedar una alarma
      // inactiva sonando de verdad (se desactivó al normalizar y el audio
      // sigue vivo). Se consulta al sistema para blindarla igual que en el
      // arranque en frío.
      final idsSonando = await _idsSonandoAhora();
      // Nada sonando: momento seguro para reparar lo que el sistema haya perdido.
      // Normalizar primero: una alarma activa vencida (el OEM canceló su
      // AlarmManager antes de disparar) debe tener su hora recalculada ANTES
      // de auditar, o la auditoría no la vería como "futura" y la ignoraría.
      final huboCambios = _normalizarAlarmasVencidas(idsSonando: idsSonando);
      await _auditarAlarmasProgramadas(idsSonando: idsSonando);
      if (huboCambios) {
        await _guardarAlarmas();
        _view.onAlarmaActualizada();
      }
      return;
    }

    final sigueSonando = await _alarmService.alarmIsRinging(_alarmaSonando!.id);

    if (!sigueSonando) {
      // Detenida externamente — misma limpieza que detecta el stream de
      // `Alarm.ringing`; comparten método a propósito (ver #7 de la revisión:
      // los dos bloques duplicados ya habían divergido).
      await _limpiarAlarmaSonandoExterna(_alarmaSonando!);
      return;
    }

    // Sigue sonando — mostrar pantalla solo si no hay una ruta ya apilada.
    if (!_alertaEnPantalla) {
      _alertaEnPantalla = true;
      _log('Pantalla de alarma mostrada al volver a primer plano '
          '(la alarma seguía sonando)');
      _view.onMostrarPantallaAlarma(_alarmaSonando!);
    }
  }

  /// IDs de la lista actual cuya alarma nativa está sonando EN ESTE MOMENTO.
  ///
  /// Se consulta al sistema (no a nuestro estado) porque tras un arranque en
  /// frío no hay estado: el proceso murió mientras sonaba. Se recorre toda la
  /// lista, también las inactivas: una alarma de una sola vez que ya se
  /// desactivó en un arranque anterior puede seguir sonando, porque
  /// `androidStopAlarmOnTermination: false` mantiene vivo el servicio.
  Future<Set<int>> _idsSonandoAhora() async {
    final ids = <int>{};
    for (final alarma in _alarmas) {
      try {
        if (await _alarmService.alarmIsRinging(alarma.id)) ids.add(alarma.id);
      } catch (e) {
        _log('⚠ ERROR al consultar si la alarma #${alarma.id} suena: $e');
      }
    }
    return ids;
  }

  /// Abre la pantalla de alarma a petición del banner de foreground.
  ///
  /// La vista NO debe llamar a `onMostrarPantallaAlarma` por su cuenta: pasando
  /// por aquí queda marcado que ya hay una alerta en pantalla y `onAppResumed`
  /// no apila una segunda ruta con el botón atrás bloqueado.
  void mostrarPantallaAlarmaDesdeBanner(Alarma alarma) {
    _alertaEnPantalla = true;
    _view.onMostrarPantallaAlarma(alarma);
  }

  /// Compara lo que DEBERÍA estar programado con lo que el sistema tiene.
  ///
  /// - Huérfanas (en el sistema pero no en nuestra lista activa) → se cancelan.
  /// - Faltantes (activas y futuras pero ausentes del sistema) → se perdieron
  ///   por un reinicio o porque el OEM canceló el AlarmManager; se reprograman.
  ///
  /// Las huérfanas se calculan contra TODAS las activas, sin filtrar por hora
  /// futura, para no cancelar una alarma que está sonando ahora mismo.
  ///
  /// [idsSonando] son las alarmas que el sistema reporta sonando AHORA. Se
  /// excluyen del barrido de huérfanas pase lo que pase, incluso si ya no
  /// figuran como activas: en el segundo arranque en frío de una alarma de
  /// una sola vez, la normalización del arranque anterior la dejó
  /// `activa = false` y persistida, pero su alarma nativa sigue sonando
  /// (solo se desregistra con `Alarm.stop`). Sin esta exclusión se clasifica
  /// como huérfana y se silencia. También se excluyen de la reparación:
  /// `programar()` ejecuta `Alarm.set`, que empieza por `Alarm.stop` sobre el
  /// mismo id y mataría el audio.
  ///
  /// Cada operación va en su propio try/catch: una alarma que lance no debe
  /// impedir que las demás se auditen o se repongan.
  ///
  /// Devuelve los IDs que faltaban.
  Future<Set<int>> _auditarAlarmasProgramadas({
    Set<int> idsSonando = const {},
  }) async {
    final idsActivas = _alarmas.where((a) => a.activa).map((a) => a.id).toSet();
    final ahora = DateTime.now();
    final activasFuturas = _alarmas
        .where((a) =>
            a.activa && a.hora.isAfter(ahora) && !idsSonando.contains(a.id))
        .toList();

    final alarmasNativas = await _alarmService.getAlarmasNativas();
    final idsNativas = alarmasNativas.map((n) => n.id).toSet();

    for (final nativa in alarmasNativas) {
      if (idsActivas.contains(nativa.id)) continue;
      if (idsSonando.contains(nativa.id)) {
        _log('Alarma #${nativa.id} suena ahora mismo: se respeta aunque ya no '
            'figure como activa (la gestionará el usuario al atenderla)');
        continue;
      }
      try {
        await _alarmService.detener(nativa.id);
        if (nativa.id > offsetAlarmaRecordatorioHeredado) {
          _log('Recordatorio antiguo #${nativa.id} cancelado: los recordatorios '
              'ya no se programan como alarmas');
        }
      } catch (e) {
        _log('⚠ ERROR al cancelar la alarma huérfana #${nativa.id}: $e');
      }
    }

    final faltantes =
        activasFuturas.map((a) => a.id).toSet().difference(idsNativas);

    if (faltantes.isEmpty) {
      _log('Auditoría: ${idsActivas.length} alarma(s) activa(s), '
          'todas presentes en el sistema. OK');
    } else {
      _log('⚠ Auditoría: alarma(s) $faltantes FALTABAN en el sistema '
          '(posible reinicio o cancelación por el OEM). Reprogramando…');
      for (final alarma in activasFuturas.where((a) => faltantes.contains(a.id))) {
        try {
          await _alarmService.programar(alarma);
          await _recordatorioService.programar(alarma);
        } catch (e) {
          _log('⚠ ERROR al reponer la alarma #${alarma.id} '
              '"${alarma.etiqueta}" en la auditoría: $e — se continúa con '
              'las demás');
        }
      }
    }

    return faltantes;
  }

  /// Recalcula alarmas activas cuya `hora` ya venció (incluyendo snoozes
  /// expirados), usando `horaDelDia`/`minutoDelDia` como referencia canónica:
  /// - Una sola vez → se desactiva.
  /// - Recurrente → se recalcula la próxima fecha de disparo.
  /// En ambos casos se limpia `pospuesta` y `confirmacionPendiente`.
  ///
  /// ⚠ El orden respecto a [_auditarAlarmasProgramadas] IMPORTA y es distinto
  /// según quién llama, a propósito — no lo unifiques sin releer esto:
  ///
  /// - En [onAppResumed] se llama ANTES de auditar. Ahí no puede haber una
  ///   alarma sonando de una sola vez con hora vencida (ese caso sale por el
  ///   guard de `_alarmaSonando` antes de llegar aquí), así que es seguro
  ///   desactivarla primero; y hace falta, porque si no se normaliza antes,
  ///   una alarma activa vencida que el sistema perdió nunca se vería como
  ///   "faltante" (la auditoría solo repone activas con hora futura).
  /// - En [_cargarAlarmas] se llama DESPUÉS de auditar. Justo al arrancar SÍ
  ///   puede existir una alarma de una sola vez que sigue sonando (el OEM
  ///   mató el proceso mientras sonaba y se reabre la app): su `hora` ya está
  ///   en el pasado y `activa` sigue en `true`. Si se normalizara antes de
  ///   auditar, quedaría `activa = false` y la auditoría, al no verla ya en
  ///   `idsActivas`, la trataría como huérfana y la cancelaría — silenciando
  ///   una alarma que sigue sonando. Auditando primero, todavía cuenta como
  ///   activa y queda protegida; la normalización llega después y la
  ///   desactiva sin tocar el audio. El bucle final de `_cargarAlarmas`
  ///   (reprogramar activas con hora futura) cubre el reprogramado de las
  ///   vencidas recurrentes que la normalización acaba de recalcular.
  ///
  /// [idsSonando] son las alarmas que el sistema reporta sonando AHORA: se
  /// dejan intactas. Recalcular la hora de una alarma que suena la volvería
  /// "futura" y el bucle de reprogramación de [_cargarAlarmas] la pasaría por
  /// `Alarm.set`, que empieza deteniéndola y mata el audio; desactivar una de
  /// una sola vez la convierte en huérfana para el siguiente arranque. De
  /// ambos casos ya se encarga [detenerAlarma] cuando el usuario la atiende.
  ///
  /// Devuelve true si se modificó alguna alarma.
  bool _normalizarAlarmasVencidas({Set<int> idsSonando = const {}}) {
    final ahora = DateTime.now();
    var huboCambios = false;

    for (final alarma in _alarmas) {
      if (idsSonando.contains(alarma.id)) continue;
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
    }

    return huboCambios;
  }

  /// Carga las alarmas desde almacenamiento persistente.
  ///
  /// Si encuentra alarmas vencidas (incluyendo snoozes expirados), recalcula
  /// su próxima fecha de disparo usando horaDelDia/minutoDelDia.
  /// Limpia alarmas nativas huérfanas que no están en SharedPreferences.
  Future<void> _cargarAlarmas() async {
    // Todo el cuerpo va en un try/finally porque el aviso a la vista NO es
    // opcional: si algo de aquí dentro lanza (canal nativo caído, DataStore
    // ilegible), _alarmas puede tener ya los datos buenos y la vista se
    // quedaría congelada en la lista anterior —vacía en el arranque—. La
    // persona abriría la app y no vería NINGUNA alarma aunque estén todas
    // guardadas. La excepción sigue subiendo a iniciar(), que la registra.
    try {
      await _cuerpoCargarAlarmas();
    } finally {
      _view.onAlarmasCargadas();
    }
  }

  /// Cuerpo real de [_cargarAlarmas]. Ver allí por qué está separado.
  Future<void> _cuerpoCargarAlarmas() async {
    final resultado = await _storageService.cargarAlarmas();
    _alarmas = resultado.alarmas;
    _nextId = resultado.nextId;

    // Averiguar PRIMERO qué está sonando ahora mismo. Puede haber una alarma
    // sonando en un arranque en frío: el proceso murió (o nunca existió) y el
    // full-screen intent acaba de lanzar la activity. Esas alarmas se saltan
    // por completo — ni se auditan, ni se normalizan, ni se reprograman —
    // porque cualquiera de las tres cosas acaba llamando a `Alarm.stop` sobre
    // ellas y apagando el audio a los 2-4 segundos, sin pantalla ninguna
    // (el `_ringing.removeById` del package ocurre antes de que
    // _iniciarEscuchaRinging() se suscriba, así que _onAlarmaSonando ni se
    // entera). Las gestionan _onAlarmaSonando / detenerAlarma a su tiempo.
    final idsSonando = await _idsSonandoAhora();
    // Se recuerda quién sonaba YA al arrancar: cuando el evento sembrado de
    // `Alarm.ringing` llegue, _onAlarmaSonando sabrá que la app se abrió POR
    // esa alarma y mostrará la pantalla completa en vez del banner.
    _idsSonandoAlArrancar
      ..clear()
      ..addAll(idsSonando);
    if (idsSonando.isNotEmpty) {
      _log('Arranque con alarma(s) $idsSonando SONANDO: se dejan intactas '
          '(no se auditan, normalizan ni reprograman)');
    }

    // Auditar ANTES de normalizar: si una alarma de una sola vez sigue
    // sonando (hora ya vencida, activa == true) porque el OEM mató el
    // proceso mientras sonaba, auditar primero la mantiene contando como
    // "activa" y evita que la huérfana la cancele y silencie el audio. Ver
    // el comentario de _normalizarAlarmasVencidas para el detalle completo.
    await _auditarAlarmasProgramadas(idsSonando: idsSonando);
    final huboCambios = _normalizarAlarmasVencidas(idsSonando: idsSonando);

    final ahora = DateTime.now();

    for (final alarma in _alarmas) {
      if (idsSonando.contains(alarma.id)) continue;
      if (alarma.activa && alarma.hora.isAfter(ahora)) {
        // Try/catch por alarma: si la #1 lanza (canal nativo, id inválido…)
        // las #2..#N tienen que programarse igual. Sin esto, el catch de
        // iniciar() se traga el error y la app parece sana con todas las
        // alarmas siguientes sin programar.
        try {
          await _alarmService.programar(alarma);
          // Reprogramar recordatorio si quedan más de 30 minutos.
          await _recordatorioService.programar(alarma);
        } catch (e) {
          _log('⚠ ERROR al reprogramar la alarma #${alarma.id} '
              '"${alarma.etiqueta}" al cargar: $e — se continúa con las demás');
        }
      }
    }

    if (huboCambios) await _guardarAlarmas();
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
    await _recordatorioService.programar(nuevaAlarma);
    _alarmas.add(nuevaAlarma);
    await _guardarAlarmas();
    _log('Alarma #${nuevaAlarma.id} "${nuevaAlarma.etiqueta}" programada → '
        '${formatearHoraAMPM(nuevaAlarma.hora)} '
        '(${nuevaAlarma.diasSemana.isEmpty ? "una vez" : "repetida"})');
    _view.onAlarmaAgregada();
  }

  /// Activa o desactiva una alarma existente.
  Future<void> toggleAlarma(Alarma alarma, bool activa) async {
    if (activa) {
      alarma.hora = proximaFecha(alarma.horaDelDia, alarma.minutoDelDia, alarma.diasSemana);
      alarma.pospuesta = false;
      await _alarmService.programar(alarma);
      await _recordatorioService.programar(alarma);
    } else {
      await _alarmService.detener(alarma.id);
      await _recordatorioService.cancelar(alarma.id);
    }
    alarma.activa = activa;
    await _guardarAlarmas();
    _log('Alarma #${alarma.id} "${alarma.etiqueta}" '
        '${activa ? "ACTIVADA" : "desactivada"} por el usuario');
    _view.onAlarmaActualizada();
  }

  /// Elimina una alarma del sistema y de la lista local.
  Future<void> eliminarAlarma(Alarma alarma) async {
    await _alarmService.detener(alarma.id);
    await _recordatorioService.cancelar(alarma.id);
    _alarmas.remove(alarma);
    await _guardarAlarmas();
    _log('Alarma #${alarma.id} "${alarma.etiqueta}" eliminada por el usuario');
    _view.onAlarmaEliminada();
  }

  /// Restaura una alarma previamente eliminada (para undo).
  Future<void> restaurarAlarma(Alarma alarma) async {
    _alarmas.add(alarma);
    if (alarma.activa) {
      alarma.hora = proximaFecha(alarma.horaDelDia, alarma.minutoDelDia, alarma.diasSemana);
      alarma.pospuesta = false;
      await _alarmService.programar(alarma);
      await _recordatorioService.programar(alarma);
    }
    await _guardarAlarmas();
    _log('Alarma #${alarma.id} "${alarma.etiqueta}" restaurada (deshacer)');
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
      // Deja el recordatorio con la hora nueva, o ninguno si ya no procede:
      // programar() se encarga de retirar el anterior en ese caso.
      await _recordatorioService.programar(alarma);
    }
    await _guardarAlarmas();
    _view.onAlarmaActualizada();
  }

  /// Actualiza la etiqueta de una alarma y la reprograma si está activa.
  Future<void> actualizarEtiqueta(Alarma alarma, String nuevaEtiqueta) async {
    alarma.etiqueta = nuevaEtiqueta.trim().isEmpty ? 'Alarma' : nuevaEtiqueta.trim();
    if (alarma.activa) {
      await _alarmService.programar(alarma);
      // Reprograma el recordatorio para que muestre la etiqueta actualizada.
      await _recordatorioService.programar(alarma);
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
      // Actualiza el recordatorio con la nueva próxima fecha de disparo.
      await _recordatorioService.programar(alarma);
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
        await _recordatorioService.programar(alarma);
      }
    }
    await _guardarAlarmas();
    _log('Alarma #${alarma.id} "${alarma.etiqueta}" editada por el usuario');
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
      await _recordatorioService.cancelar(alarma.id);
      alarma.hora = DateTime.now().add(const Duration(minutes: 5));
      alarma.pospuesta = true;
      await _alarmService.programar(alarma);
      await _guardarAlarmas();
      _alarmaSonando = null;
      _alertaEnPantalla = false;
      _log('Alarma #${alarma.id} pospuesta 5 min por el usuario');
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
      _log('Alarma #${alarma.id} detenida por el usuario (desde la app)');
      await _alarmService.detener(alarma.id);
      // Cancelar siempre el recordatorio del ciclo actual.
      await _recordatorioService.cancelar(alarma.id);
      alarma.pospuesta = false;
      alarma.confirmacionPendiente = false;

      if (alarma.diasSemana.isNotEmpty) {
        // Recurrente: siempre reprogramar (con o sin confirmación).
        // Usar horaDelDia/minutoDelDia: alarma.hora puede contener la hora del snooze/confirmación.
        alarma.hora = proximaFecha(alarma.horaDelDia, alarma.minutoDelDia, alarma.diasSemana);
        await _alarmService.programar(alarma);
        // Programar recordatorio para el próximo disparo.
        await _recordatorioService.programar(alarma);
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
      await _recordatorioService.cancelar(alarma.id);
      alarma.confirmacionPendiente = true;
      alarma.pospuesta = false;

      // Programar el re-sonido tras la ventana de confirmación.
      alarma.hora = DateTime.now().add(duracionConfirmacion);
      await _alarmService.programar(alarma);

      await _guardarAlarmas();
      _log('Alarma #${alarma.id} "${alarma.etiqueta}" cerrada con confirmación: '
          're-sonará en ${duracionConfirmacion.inSeconds}s para confirmar despertar');

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
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _suscripcionRinging?.cancel();
    ahoraNotifier.dispose();
  }
}
