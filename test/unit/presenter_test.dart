import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:despertador_novia/models/alarma.dart';
import 'package:despertador_novia/presenters/alarmas_presenter.dart';
import 'package:despertador_novia/services/alarm_service.dart';
import 'package:despertador_novia/services/permission_service.dart';
import 'package:despertador_novia/services/recordatorio_service.dart';
import 'package:despertador_novia/services/storage_service.dart';

import 'dobles_notificaciones.dart';

// ─── Fakes ────────────────────────────────────────────────────────────────────

class FakeAlarmService extends AlarmService {
  final List<Alarma> programadas = [];
  final List<int> detenidas = [];
  final Set<int> sonandoIds = {};
  List<AlarmSettings> alarmasNativas = [];

  /// IDs cuya programación lanza, para simular un fallo del canal nativo en
  /// una alarma concreta sin afectar a las demás.
  final Set<int> idsQueFallanAlProgramar = {};

  final StreamController<AlarmSet> ringingController = StreamController<AlarmSet>.broadcast();

  @override
  Future<void> init() async {}

  @override
  Future<void> programar(Alarma alarma) async {
    if (idsQueFallanAlProgramar.contains(alarma.id)) {
      throw StateError('fallo simulado al programar #${alarma.id}');
    }
    programadas.removeWhere((a) => a.id == alarma.id);
    programadas.add(alarma.copyWith());
  }

  @override
  Future<void> detener(int id) async {
    detenidas.add(id);
    sonandoIds.remove(id);
    // Fidelidad con el package real: `Alarm.stop` borra la alarma del
    // AlarmStorage, así que deja de aparecer en `Alarm.getAlarms()`. Sin esto
    // el doble mentía: una alarma cancelada seguía figurando como nativa, y la
    // auditoría podía "cubrir" bugs de capas anteriores (la purga de
    // recordatorios heredados quedaba indistinguible de la auditoría).
    //
    // Se reemplaza la lista en vez de mutarla: la auditoría itera sobre la
    // lista que devolvió getAlarmasNativas() y mutarla in situ la rompería con
    // un ConcurrentModificationError.
    alarmasNativas =
        alarmasNativas.where((nativa) => nativa.id != id).toList();
  }

  @override
  Future<bool> alarmIsRinging(int id) async => sonandoIds.contains(id);

  /// Si es true, getAlarmasNativas lanza: simula el canal nativo caído a
  /// mitad de la carga de alarmas.
  bool lanzarEnGetAlarmasNativas = false;

  /// Copia defensiva, como el servicio real: `Alarm.getAlarms()` construye una
  /// lista nueva en cada llamada.
  @override
  Future<List<AlarmSettings>> getAlarmasNativas() async {
    if (lanzarEnGetAlarmasNativas) {
      throw StateError('fallo simulado al consultar las alarmas nativas');
    }
    return List<AlarmSettings>.of(alarmasNativas);
  }

  @override
  Stream<AlarmSet> get ringingStream => ringingController.stream;
}

class FakeRecordatorioService extends RecordatorioService {
  FakeRecordatorioService() : super(planificador: PlanificadorFalso());

  final Set<int> programados = {};
  final List<int> cancelados = [];

  @override
  Future<void> programar(Alarma alarma) async {
    programados.add(alarma.id);
  }

  @override
  Future<void> cancelar(int alarmaId) async {
    programados.remove(alarmaId);
    cancelados.add(alarmaId);
  }
}

class FakeStorageService extends StorageService {
  List<Alarma> _alarmas = [];
  int _nextId = 1;
  int saveCount = 0;

  void precargar(List<Alarma> alarmas, {int nextId = 1}) {
    _alarmas = alarmas.map((a) => a.copyWith()).toList();
    _nextId = nextId;
  }

  @override
  Future<void> guardarAlarmas(List<Alarma> alarmas, int nextId) async {
    _alarmas = alarmas.map((a) => a.copyWith()).toList();
    _nextId = nextId;
    saveCount++;
  }

  @override
  Future<({List<Alarma> alarmas, int nextId})> cargarAlarmas() async {
    return (alarmas: _alarmas.map((a) => a.copyWith()).toList(), nextId: _nextId);
  }

  bool _autostartAtendido = false;

  @override
  Future<void> guardarAutostartAtendido() async => _autostartAtendido = true;

  @override
  Future<bool> cargarAutostartAtendido() async => _autostartAtendido;
}

class FakePermissionService extends PermissionService {
  /// Controla el estado de full-screen intent devuelto por obtenerEstadoPermisos.
  bool fullScreenIntentConcedido = true;

  @override
  Future<EstadoPermisos> obtenerEstadoPermisos() async => EstadoPermisos(
        alarmasExactas: true,
        notificaciones: true,
        exencionBateria: true,
        fullScreenIntent: fullScreenIntentConcedido,
        noMolestar: false,
      );

  @override
  Future<bool> verificarPermisoAlarmasExactas() async => true;
  @override
  Future<void> solicitarPermisoAlarmasExactas() async {}
  @override
  Future<bool> verificarModoNoMolestar() async => false;
  @override
  Future<bool> verificarPermisoNotificaciones() async => true;
  @override
  Future<void> solicitarPermisoNotificaciones() async {}
  @override
  Future<void> verificarYSolicitarPermisoAlarmasExactas() async {}

  /// Controla si la app aparece como exenta de optimización de batería.
  /// Con false, `iniciar()` llama a [solicitarExencionBateria], que en un
  /// dispositivo real abre un diálogo del sistema (y provoca un `resumed`).
  bool exentoBateria = true;

  /// Se ejecuta dentro de [solicitarExencionBateria]. Simula lo que ocurre al
  /// cerrar el diálogo del sistema a mitad de `iniciar()`.
  Future<void> Function()? alSolicitarExencionBateria;

  @override
  Future<bool> verificarExencionBateria() async => exentoBateria;
  @override
  Future<void> solicitarExencionBateria() async {
    final gancho = alSolicitarExencionBateria;
    if (gancho != null) await gancho();
  }

  /// Controla si el fabricante simulado mata apps de forma agresiva.
  bool fabricanteAgresivo = false;

  /// Si es true, esFabricanteAgresivo() lanza una excepción: simula un fallo
  /// inesperado (no un PlatformException, que ya se atrapa dentro del
  /// servicio real) durante el bloque de permisos/diagnóstico de iniciar().
  bool lanzarErrorEnFabricanteAgresivo = false;

  @override
  Future<bool> esFabricanteAgresivo() async {
    if (lanzarErrorEnFabricanteAgresivo) {
      throw Exception('fallo simulado en esFabricanteAgresivo');
    }
    return fabricanteAgresivo;
  }

  /// Simula si alguno de los componentes OEM de "Inicio automático" resolvió.
  /// Con false el usuario acaba en los ajustes genéricos sin ver la pantalla
  /// del fabricante, así que el aviso NO debe darse por atendido.
  bool autostartSeAbre = true;

  @override
  Future<bool> abrirAutostartOEM() async => autostartSeAbre;
}

class FakeView implements AlarmasView {
  int cargadasCount = 0;
  int agregadasCount = 0;
  int actualizadasCount = 0;
  int eliminadasCount = 0;
  bool permisoNecesario = false;
  bool modoNoMolestar = false;
  Alarma? ultimaAlarmaRinging;
  Alarma? ultimaAlarmaForeground;

  @override
  void onAlarmasCargadas() => cargadasCount++;
  @override
  void onAlarmaAgregada() => agregadasCount++;
  @override
  void onAlarmaActualizada() => actualizadasCount++;
  @override
  void onAlarmaEliminada() => eliminadasCount++;
  @override
  void onPermisoNecesario(bool necesita) => permisoNecesario = necesita;
  @override
  void onModoNoMolestarCambiado(bool activo) => modoNoMolestar = activo;
  bool fullScreenDenegado = false;
  @override
  void onFullScreenIntentDenegado(bool denegado) => fullScreenDenegado = denegado;
  @override
  void onMostrarPantallaAlarma(Alarma alarma) => ultimaAlarmaRinging = alarma;
  @override
  void onAlarmaSonandoEnForeground(Alarma alarma) => ultimaAlarmaForeground = alarma;
  bool autostartRecomendado = false;
  @override
  void onAutostartRecomendado(bool recomendado) =>
      autostartRecomendado = recomendado;
  @override
  BuildContext getContext() => throw UnimplementedError();
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

Alarma _alarmaSimple({
  int id = 1,
  int hora = 7,
  int minuto = 0,
  bool activa = true,
  bool pospuesta = false,
  List<int>? diasSemana,
}) {
  return Alarma(
    id: id,
    hora: DateTime(2030, 6, 1, hora, minuto),
    etiqueta: 'Test $id',
    activa: activa,
    pospuesta: pospuesta,
    diasSemana: diasSemana ?? [],
    horaDelDia: hora,
    minutoDelDia: minuto,
  );
}

AlarmSettings _settingsDummy(int id) {
  return AlarmSettings(
    id: id,
    dateTime: DateTime.now(),
    volumeSettings: const VolumeSettings.fixed(volume: 1.0, volumeEnforced: true),
    notificationSettings: const NotificationSettings(
      title: 'Test',
      body: 'Test',
      stopButton: 'Stop',
    ),
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AlarmasPresenter presenter;
  late FakeView view;
  late FakeAlarmService alarm;
  late FakeStorageService storage;
  late FakeRecordatorioService recordatorio;
  late List<String> eventosLog;

  setUp(() {
    view = FakeView();
    alarm = FakeAlarmService();
    storage = FakeStorageService();
    recordatorio = FakeRecordatorioService();
    eventosLog = [];
    // El presenter consulta WidgetsBinding.instance.lifecycleState para decidir
    // entre banner (app visible) y pantalla completa (app en segundo plano).
    // En el entorno de test ese valor es null por defecto: se fija a "resumed"
    // para simular la app en primer plano, como en un dispositivo real.
    TestWidgetsFlutterBinding.instance
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  tearDown(() {
    presenter.dispose();
    alarm.ringingController.close();
  });

  // Crea el presenter, llama iniciar() y lo registra para dispose en tearDown.
  Future<void> arrancar({List<Alarma> alarmas = const []}) async {
    storage.precargar(alarmas);
    presenter = AlarmasPresenter(
      view: view,
      alarmService: alarm,
      storageService: storage,
      permissionService: FakePermissionService(),
      recordatorioService: recordatorio,
      registro: eventosLog.add,
    );
    await presenter.iniciar();
  }

  // ── agregarAlarma ──────────────────────────────────────────────────────────

  group('agregarAlarma', () {
    test('agrega alarma y notifica a la vista', () async {
      await arrancar();
      view.agregadasCount = 0;

      await presenter.agregarAlarma(
        hora: 8,
        minuto: 30,
        etiqueta: 'Reunión',
        diasSemana: [],
      );

      expect(presenter.alarmas, hasLength(1));
      expect(presenter.alarmas.first.etiqueta, 'Reunión');
      expect(alarm.programadas, hasLength(1));
      expect(view.agregadasCount, 1);
    });

    test('etiqueta vacía se reemplaza por "Alarma"', () async {
      await arrancar();
      await presenter.agregarAlarma(hora: 8, minuto: 0, etiqueta: '   ', diasSemana: []);
      expect(presenter.alarmas.first.etiqueta, 'Alarma');
    });

    test('los IDs se auto-incrementan sin colisión', () async {
      await arrancar();
      await presenter.agregarAlarma(hora: 7, minuto: 0, etiqueta: 'A', diasSemana: []);
      await presenter.agregarAlarma(hora: 8, minuto: 0, etiqueta: 'B', diasSemana: []);

      final ids = presenter.alarmas.map((a) => a.id).toSet();
      expect(ids, hasLength(2));
    });

    test('la hora calculada siempre es futura', () async {
      await arrancar();
      await presenter.agregarAlarma(hora: 23, minuto: 59, etiqueta: 'Tarde', diasSemana: []);
      expect(presenter.alarmas.first.hora.isAfter(DateTime.now()), isTrue);
    });
  });

  // ── toggleAlarma ───────────────────────────────────────────────────────────

  group('toggleAlarma', () {
    test('reactivar recalcula hora futura aunque la original sea pasada', () async {
      final alarmaVieja = _alarmaSimple(hora: 7, activa: false);
      alarmaVieja.hora = DateTime(2020, 1, 1, 7, 0);
      await arrancar(alarmas: [alarmaVieja]);

      await presenter.toggleAlarma(presenter.alarmas.first, true);

      final programada = alarm.programadas.last;
      expect(programada.hora.isAfter(DateTime.now()), isTrue);
      expect(presenter.alarmas.first.activa, isTrue);
    });

    test('reactivar limpia pospuesta', () async {
      final a = _alarmaSimple(activa: false, pospuesta: true);
      await arrancar(alarmas: [a]);

      await presenter.toggleAlarma(presenter.alarmas.first, true);
      expect(presenter.alarmas.first.pospuesta, isFalse);
    });

    test('desactivar detiene la alarma nativa', () async {
      await arrancar(alarmas: [_alarmaSimple(id: 5, activa: true)]);
      alarm.detenidas.clear();

      await presenter.toggleAlarma(presenter.alarmas.first, false);

      expect(alarm.detenidas, contains(5));
      expect(presenter.alarmas.first.activa, isFalse);
    });
  });

  // ── detenerAlarma — bug alarma fantasma ────────────────────────────────────

  group('detenerAlarma — prevención de alarma fantasma', () {
    test('alarma de una sola vez queda inactiva tras detener', () async {
      await arrancar(alarmas: [_alarmaSimple(id: 1, diasSemana: [])]);

      await presenter.detenerAlarma(presenter.alarmas.first);

      expect(presenter.alarmas.first.activa, isFalse,
          reason: 'Una alarma de una sola vez debe desactivarse al apagarse');
    });

    test('alarma recurrente se reprograma y sigue activa', () async {
      await arrancar(alarmas: [_alarmaSimple(id: 2, diasSemana: [1, 2, 3, 4, 5])]);
      alarm.programadas.clear();

      await presenter.detenerAlarma(presenter.alarmas.first);

      expect(presenter.alarmas.first.activa, isTrue);
      expect(alarm.programadas, hasLength(1),
          reason: 'Debe re-programarse para la próxima ocurrencia');
      expect(alarm.programadas.first.hora.isAfter(DateTime.now()), isTrue);
    });

    test('alarma de una sola vez no se reprograma al reiniciar la app', () async {
      await arrancar(alarmas: [_alarmaSimple(id: 3, diasSemana: [])]);
      await presenter.detenerAlarma(presenter.alarmas.first);
      expect(presenter.alarmas.first.activa, isFalse);

      // Simular reinicio: segundo presenter cargando desde el mismo storage
      alarm.programadas.clear();
      presenter.dispose();
      presenter = AlarmasPresenter(
        view: FakeView(),
        alarmService: alarm,
        storageService: storage,
        permissionService: FakePermissionService(),
        recordatorioService: recordatorio,
      );
      await presenter.iniciar();

      expect(presenter.alarmas.first.activa, isFalse,
          reason: 'No debe re-activarse una alarma de una sola vez apagada');
      expect(alarm.programadas.where((a) => a.id == 3), isEmpty,
          reason: 'No debe re-programarse una alarma inactiva');
    });

    test('alarma de una sola vez con hora vencida se desactiva al cargar', () async {
      final a = _alarmaSimple(id: 4, activa: true, diasSemana: []);
      a.hora = DateTime(2020, 1, 1, 7, 0); // en el pasado
      await arrancar(alarmas: [a]);

      expect(presenter.alarmas.first.activa, isFalse,
          reason: 'Al cargar, una alarma de una sola vez vencida debe desactivarse');
      expect(alarm.programadas.where((p) => p.id == 4), isEmpty,
          reason: 'No debe reprogramarse una alarma de una sola vez vencida');
    });

    test('alarma recurrente con hora vencida se reprograma al cargar', () async {
      final a = _alarmaSimple(id: 5, activa: true, diasSemana: [1, 2, 3, 4, 5, 6, 7]);
      a.hora = DateTime(2020, 1, 1, 7, 0);
      await arrancar(alarmas: [a]);

      expect(presenter.alarmas.first.activa, isTrue);
      final prog = alarm.programadas.where((p) => p.id == 5);
      expect(prog, isNotEmpty);
      expect(prog.first.hora.isAfter(DateTime.now()), isTrue);
    });
  });

  // ── posponerAlarma ─────────────────────────────────────────────────────────

  group('posponerAlarma', () {
    test('programa snooze entre 4 y 6 minutos en el futuro', () async {
      await arrancar(alarmas: [_alarmaSimple(id: 1)]);
      alarm.programadas.clear();
      alarm.detenidas.clear();

      await presenter.posponerAlarma(presenter.alarmas.first);

      final ahora = DateTime.now();
      final programada = alarm.programadas.last;
      expect(programada.hora.isAfter(ahora.add(const Duration(minutes: 4))), isTrue);
      expect(programada.hora.isBefore(ahora.add(const Duration(minutes: 6))), isTrue);
      expect(presenter.alarmas.first.pospuesta, isTrue);
    });

    test('detiene el audio actual antes de reprogramar', () async {
      await arrancar(alarmas: [_alarmaSimple(id: 99)]);
      alarm.detenidas.clear();

      await presenter.posponerAlarma(presenter.alarmas.first);

      expect(alarm.detenidas, contains(99),
          reason: 'Debe llamar detener() antes de reprogramar el snooze');
    });

    test('no altera horaDelDia ni minutoDelDia', () async {
      await arrancar(alarmas: [_alarmaSimple(id: 1, hora: 7, minuto: 30)]);

      await presenter.posponerAlarma(presenter.alarmas.first);

      expect(presenter.alarmas.first.horaDelDia, 7);
      expect(presenter.alarmas.first.minutoDelDia, 30);
    });
  });

  // ── restaurarAlarma (undo) ─────────────────────────────────────────────────

  group('restaurarAlarma', () {
    test('restaurar recalcula hora futura antes de reprogramar', () async {
      await arrancar();
      alarm.programadas.clear();

      final vieja = _alarmaSimple(id: 1, activa: true);
      vieja.hora = DateTime(2020, 1, 1, 6, 0);

      await presenter.restaurarAlarma(vieja);

      final programada = alarm.programadas.last;
      expect(programada.hora.isAfter(DateTime.now()), isTrue);
    });

    test('alarma inactiva restaurada no se reprograma', () async {
      await arrancar();
      alarm.programadas.clear();

      final inactiva = _alarmaSimple(id: 1, activa: false);
      await presenter.restaurarAlarma(inactiva);

      expect(alarm.programadas, isEmpty);
      expect(presenter.alarmas.first.activa, isFalse);
    });
  });

  // ── eliminarAlarma ─────────────────────────────────────────────────────────

  group('eliminarAlarma', () {
    test('elimina de la lista, detiene la nativa y notifica', () async {
      await arrancar(alarmas: [_alarmaSimple(id: 7)]);
      alarm.detenidas.clear();
      view.eliminadasCount = 0;

      await presenter.eliminarAlarma(presenter.alarmas.first);

      expect(presenter.alarmas, isEmpty);
      expect(alarm.detenidas, contains(7));
      expect(view.eliminadasCount, 1);
    });
  });

  // ── onAppResumed — race condition fix ──────────────────────────────────────

  group('onAppResumed', () {
    test('muestra pantalla aunque _alarmaSonando fuera null por race condition', () async {
      await arrancar(alarmas: [_alarmaSimple(id: 1, activa: true)]);

      // Simular que la alarma está sonando pero el stream aún no disparó
      alarm.sonandoIds.add(1);

      await presenter.onAppResumed();

      expect(view.ultimaAlarmaRinging, isNotNull,
          reason: 'Debe mostrar la pantalla aunque _alarmaSonando era null');
    });

    test('no muestra pantalla si no hay ninguna alarma sonando', () async {
      await arrancar(alarmas: [_alarmaSimple(id: 1, activa: true)]);
      alarm.sonandoIds.clear();

      await presenter.onAppResumed();

      expect(view.ultimaAlarmaRinging, isNull);
    });
  });

  // ── obtenerProximaAlarma ───────────────────────────────────────────────────

  group('obtenerProximaAlarma', () {
    test('devuelve null si no hay alarmas activas', () async {
      await arrancar();
      expect(presenter.obtenerProximaAlarma(), isNull);
    });

    test('devuelve la alarma activa con hora más cercana', () async {
      final a1 = _alarmaSimple(id: 1);
      final a2 = _alarmaSimple(id: 2);
      a1.hora = DateTime.now().add(const Duration(hours: 2));
      a2.hora = DateTime.now().add(const Duration(hours: 1));
      await arrancar(alarmas: [a1, a2]);

      expect(presenter.obtenerProximaAlarma()?.id, 2);
    });

    test('ignora alarmas inactivas', () async {
      final activa = _alarmaSimple(id: 1, activa: true);
      final inactiva = _alarmaSimple(id: 2, activa: false);
      activa.hora = DateTime.now().add(const Duration(minutes: 10));
      inactiva.hora = DateTime.now().add(const Duration(minutes: 5));
      await arrancar(alarmas: [activa, inactiva]);

      expect(presenter.obtenerProximaAlarma()?.id, 1);
    });
  });

  // ── huérfanos nativos ──────────────────────────────────────────────────────

  group('limpieza de alarmas nativas huérfanas', () {
    test('alarma nativa sin entrada en lista activa se detiene al cargar', () async {
      // ID 99 existe en el paquete nativo pero no en SharedPreferences
      alarm.alarmasNativas = [
        AlarmSettings(
          id: 99,
          dateTime: DateTime.now().add(const Duration(hours: 1)),
          assetAudioPath: 'assets/audio/alarma_limpieza.wav',
          volumeSettings: const VolumeSettings.fixed(volume: 1.0),
          notificationSettings: const NotificationSettings(
            title: 'Test',
            body: 'Test body',
          ),
        ),
      ];

      await arrancar(alarmas: [_alarmaSimple(id: 1)]);

      expect(alarm.detenidas, contains(99),
          reason: 'La alarma huérfana (ID 99) debe detenerse al cargar');
    });

    test('alarma nativa con ID activo en lista NO se detiene', () async {
      alarm.alarmasNativas = [
        AlarmSettings(
          id: 1,
          dateTime: DateTime.now().add(const Duration(hours: 1)),
          assetAudioPath: 'assets/audio/alarma_limpieza.wav',
          volumeSettings: const VolumeSettings.fixed(volume: 1.0),
          notificationSettings: const NotificationSettings(
            title: 'Test',
            body: 'Test body',
          ),
        ),
      ];

      await arrancar(alarmas: [_alarmaSimple(id: 1, activa: true)]);

      expect(alarm.detenidas, isNot(contains(1)),
          reason: 'Una alarma nativa con ID activo en lista no debe detenerse');
    });

    test('un recordatorio heredado que reaparece después se cancela en la auditoría',
        () async {
      // Al arrancar no había ninguno (la purga no tiene nada que hacer). El
      // recordatorio heredado aparece más tarde: lo rearmó ArranqueReceiver
      // con el AlarmStorage que dejó la versión vieja. Esta es la red de
      // seguridad de la auditoría, distinta de la purga de `iniciar()`.
      await arrancar(alarmas: [_alarmaSimple(id: 1)]);
      alarm.alarmasNativas = [_settingsDummy(10001)];
      alarm.detenidas.clear();

      await presenter.onAppResumed();

      expect(alarm.detenidas, contains(10001));
      expect(eventosLog.any((l) => l.contains('Recordatorio antiguo #10001')),
          isTrue);
    });

    test('una alarma sonando al arrancar no se cancela como huérfana', () async {
      // Reproduce el escenario que motiva esta rama: una alarma de una sola
      // vez sigue sonando porque el OEM mató el proceso mientras sonaba y la
      // app se reabre. Su hora ya venció pero activa sigue en true, y el
      // paquete nativo (alarm.alarmasNativas) todavía la reporta porque
      // sigue sonando de verdad.
      final a = _alarmaSimple(id: 50, activa: true, diasSemana: []);
      a.hora = DateTime(2020, 1, 1, 7, 0); // vencida: ya disparó
      alarm.alarmasNativas = [_settingsDummy(50)];

      await arrancar(alarmas: [a]);

      expect(alarm.detenidas, isNot(contains(50)),
          reason: 'Si _cargarAlarmas normalizara (desactivara) esta alarma '
              'ANTES de auditar, la auditoría dejaría de verla como activa y '
              'la trataría como huérfana, llamando a Alarm.stop y '
              'silenciando una alarma que el usuario todavía no ha detenido. '
              'Auditar debe correr antes de normalizar en _cargarAlarmas.');
    });

    test('una alarma INACTIVA en almacenamiento pero SONANDO no se cancela',
        () async {
      // Aísla la guardia `if (idsSonando.contains(nativa.id)) continue;` de
      // _auditarAlarmasProgramadas, sin apoyarse en ninguna otra protección:
      // la alarma está persistida como inactiva (un arranque anterior la
      // desactivó), así que NO entra en `idsActivas` y la auditoría la ve como
      // huérfana. Solo la consulta al sistema ("¿suena ahora?") la salva.
      // Sin ese `continue`, Alarm.stop mata el audio de una alarma que la
      // persona todavía no ha atendido.
      final a = _alarmaSimple(id: 90, activa: false, diasSemana: []);
      a.hora = DateTime(2020, 1, 1, 6, 0);
      alarm.alarmasNativas = [_settingsDummy(90)];
      alarm.sonandoIds.add(90);

      await arrancar(alarmas: [a]);

      expect(alarm.detenidas, isNot(contains(90)),
          reason: 'La alarma suena AHORA: la auditoría debe respetarla aunque '
              'ya no figure como activa en el almacenamiento');
      expect(eventosLog.any((l) => l.contains('#90 suena ahora mismo')), isTrue,
          reason: 'La excepción debe quedar registrada en el diagnóstico');
    });
  });

  // ── la vista nunca se queda sin noticias ──────────────────────────────────

  group('robustez de _cargarAlarmas', () {
    test('si la carga lanza a mitad, la vista se entera igualmente', () async {
      // Sin esto la lista se queda congelada: _alarmas ya tiene los datos
      // buenos, pero onAlarmasCargadas() nunca se llama porque la excepción
      // salta antes de la última línea. El catch de iniciar() se la traga y la
      // persona abre la app y no ve NINGUNA alarma, aunque estén todas ahí.
      storage.precargar([_alarmaSimple(id: 1), _alarmaSimple(id: 2)]);
      alarm.lanzarEnGetAlarmasNativas = true;
      presenter = AlarmasPresenter(
        view: view,
        alarmService: alarm,
        storageService: storage,
        permissionService: FakePermissionService(),
        recordatorioService: recordatorio,
        registro: eventosLog.add,
      );

      await presenter.iniciar();

      expect(view.cargadasCount, greaterThan(0),
          reason: 'La vista tiene que recibir onAlarmasCargadas pase lo que '
              'pase, o se queda mostrando la lista anterior (vacía en el '
              'arranque) con las alarmas ya cargadas en memoria');
      expect(presenter.alarmas.length, 2,
          reason: 'Los datos sí se leyeron: el fallo fue posterior');
    });
  });

  // ── alarmas solapadas ─────────────────────────────────────────────────────

  group('dos alarmas sonando a la vez', () {
    test('manda la primera y el solapamiento queda registrado', () async {
      // El package descarta la segunda alarma con unsaveAlarm cuando
      // allowAlarmOverlap es false (su valor por defecto), así que el patrón
      // "alarma de respaldo 5 minutos después" NO suena y la auditoría no la
      // repone. Aquí no se puede arreglar sin forkear el package, pero tiene
      // que quedar rastro en el diagnóstico: es la única forma de reconocer
      // el patrón si la usuaria vuelve a reportar que no sonó.
      await arrancar(alarmas: [
        _alarmaSimple(id: 70, diasSemana: [1, 2, 3, 4, 5, 6, 7]),
        _alarmaSimple(id: 71, diasSemana: [1, 2, 3, 4, 5, 6, 7]),
      ]);

      alarm.ringingController
          .add(AlarmSet([_settingsDummy(70), _settingsDummy(71)]));
      await Future<void>.delayed(Duration.zero);

      expect(view.ultimaAlarmaForeground?.id, 70,
          reason: 'Se muestra la primera que empezó a sonar');
      expect(presenter.alarmaSonando?.id, 70,
          reason: 'El estado interno debe apuntar a la alarma que la persona '
              'está viendo: detenerla desde esa pantalla tiene que dejar '
              'hayAlarmaSonando en false');
      expect(eventosLog.any((l) => l.contains('#71') && l.contains('SOLAPADA')),
          isTrue,
          reason: 'Sin esta línea el patrón es invisible en el diagnóstico');
    });
  });

  // ── purga de recordatorios heredados ───────────────────────────────────────

  group('purga de recordatorios heredados', () {
    test('la purga cancela el recordatorio heredado ANTES de auditar', () async {
      // Cubre _purgarRecordatoriosHeredados de forma aislada: es la capa que
      // protege la ventana entre MY_PACKAGE_REPLACED (ArranqueReceiver rearma
      // un recordatorio de la versión vieja) y la primera apertura de la app.
      // La auditoría también cancelaría este ID, así que la prueba se ancla al
      // mensaje propio de la purga y a su posición en el log.
      alarm.alarmasNativas = [_settingsDummy(10001)];

      await arrancar(alarmas: [_alarmaSimple(id: 1)]);

      expect(alarm.detenidas, contains(10001));
      final indicePurga = eventosLog
          .indexWhere((l) => l.contains('Recordatorio heredado #10001 purgado'));
      expect(indicePurga, isNonNegative,
          reason: 'Sin la llamada a _purgarRecordatoriosHeredados en iniciar() '
              'este evento no existe: el recordatorio solo moriría más tarde, '
              'en la auditoría de _cargarAlarmas');
      final indiceAuditoria =
          eventosLog.indexWhere((l) => l.contains('Auditoría'));
      expect(indiceAuditoria, isNonNegative);
      expect(indicePurga, lessThan(indiceAuditoria),
          reason: 'La purga debe correr justo tras Alarm.init(), antes de que '
              'nada más toque el estado nativo');
    });

    test('la purga no toca las alarmas normales', () async {
      alarm.alarmasNativas = [_settingsDummy(1)];

      await arrancar(alarmas: [_alarmaSimple(id: 1, activa: true)]);

      expect(alarm.detenidas, isEmpty,
          reason: 'Solo los IDs por encima del offset heredado son '
              'recordatorios: una alarma normal jamás debe purgarse');
    });
  });

  // ── cerrarConConfirmacion ──────────────────────────────────────────────────

  group('cerrarConConfirmacion', () {
    test('detiene el audio actual antes de reprogramar', () async {
      await arrancar(alarmas: [_alarmaSimple(id: 1)]);
      alarm.detenidas.clear();

      await presenter.cerrarConConfirmacion(presenter.alarmas.first);

      expect(alarm.detenidas, contains(1),
          reason: 'Debe llamar detener() para parar el audio actual');
    });

    test('marca confirmacionPendiente y programa alarma 30s en el futuro', () async {
      await arrancar(alarmas: [_alarmaSimple(id: 1)]);
      alarm.programadas.clear();

      final antes = DateTime.now();
      await presenter.cerrarConConfirmacion(presenter.alarmas.first);
      final despues = DateTime.now();

      expect(presenter.alarmas.first.confirmacionPendiente, isTrue);
      expect(alarm.programadas, hasLength(1));
      final hora = alarm.programadas.first.hora;
      expect(
        hora.isAfter(antes.add(const Duration(seconds: 25))) &&
            hora.isBefore(despues.add(const Duration(seconds: 35))),
        isTrue,
        reason: 'La confirmación debe programarse ~30s en el futuro',
      );
    });

    test('limpia _alarmaSonando y _alertaEnPantalla', () async {
      await arrancar(alarmas: [_alarmaSimple(id: 1, activa: true)]);
      alarm.sonandoIds.add(1);
      await presenter.onAppResumed(); // establece _alarmaSonando
      view.actualizadasCount = 0;

      await presenter.cerrarConConfirmacion(presenter.alarmas.first);

      expect(presenter.hayAlarmaSonando, isFalse,
          reason: 'Tras cerrarConConfirmacion no debe haber alarma activa en UI');
      expect(view.actualizadasCount, greaterThan(0));
    });

    test('no altera horaDelDia ni minutoDelDia', () async {
      await arrancar(alarmas: [_alarmaSimple(id: 1, hora: 8, minuto: 45)]);

      await presenter.cerrarConConfirmacion(presenter.alarmas.first);

      expect(presenter.alarmas.first.horaDelDia, 8);
      expect(presenter.alarmas.first.minutoDelDia, 45);
    });
  });

  // ── detenerAlarma — confirmacion pendiente ─────────────────────────────────

  group('detenerAlarma — confirmación pendiente', () {
    test('confirmar alarma de una sola vez la desactiva definitivamente', () async {
      final a = _alarmaSimple(id: 1, diasSemana: []);
      await arrancar(alarmas: [a]);
      await presenter.cerrarConConfirmacion(presenter.alarmas.first);

      // Simular que la alarma de confirmación suena 30s después
      await presenter.detenerAlarma(presenter.alarmas.first);

      expect(presenter.alarmas.first.activa, isFalse,
          reason: 'Confirmación final: una sola vez debe desactivarse');
      expect(presenter.alarmas.first.confirmacionPendiente, isFalse);
    });

    test('confirmar alarma recurrente la reprograma (no la desactiva)', () async {
      final a = _alarmaSimple(id: 2, diasSemana: [1, 2, 3, 4, 5, 6, 7]);
      await arrancar(alarmas: [a]);
      await presenter.cerrarConConfirmacion(presenter.alarmas.first);
      alarm.programadas.clear();

      await presenter.detenerAlarma(presenter.alarmas.first);

      expect(presenter.alarmas.first.activa, isTrue,
          reason: 'Recurrente: debe seguir activa tras confirmar');
      expect(presenter.alarmas.first.confirmacionPendiente, isFalse);
      expect(alarm.programadas, hasLength(1),
          reason: 'Debe reprogramarse para la siguiente ocurrencia');
    });

    test('no hay tercer disparo: confirmar no genera nueva confirmacion', () async {
      final a = _alarmaSimple(id: 1, diasSemana: []);
      await arrancar(alarmas: [a]);

      // Primera alarma → cerrar con confirmación
      await presenter.cerrarConConfirmacion(presenter.alarmas.first);
      expect(presenter.alarmas.first.confirmacionPendiente, isTrue);

      // Segunda alarma (confirmación) → detener definitivamente
      await presenter.detenerAlarma(presenter.alarmas.first);
      expect(presenter.alarmas.first.confirmacionPendiente, isFalse);
      expect(presenter.alarmas.first.activa, isFalse,
          reason: 'No debe generarse un tercer disparo');
    });

    test('stream "alarm stopped" durante cerrarConConfirmacion no resetea confirmacionPendiente', () async {
      final a = _alarmaSimple(id: 1, diasSemana: []);
      await arrancar(alarmas: [a]);
      alarm.sonandoIds.add(1); // simular que suena

      // Disparar el primer ring
      alarm.ringingController.add(AlarmSet([_settingsDummy(1)]));
      await Future.delayed(Duration.zero); // Permitir que el stream se procese

      // Usuario desliza → cerrarConConfirmacion
      await presenter.cerrarConConfirmacion(presenter.alarmas.first);
      expect(presenter.alarmas.first.confirmacionPendiente, isTrue);

      // Simular que el stream emite "stopped" mientras cerrarConConfirmacion aún está en su ventana de 500ms
      alarm.ringingController.add(AlarmSet.empty());
      await Future.delayed(const Duration(milliseconds: 600)); // Esperar a que el Future.delayed de _idsEnDetencion.remove() termine

      expect(presenter.alarmas.first.confirmacionPendiente, isTrue,
          reason: 'El cleanup no debe limpiar confirmacionPendiente durante una detención iniciada por el usuario');
    });
  });

  // ── limpiarAlarmaSonandoExterna + confirmacion ─────────────────────────────

  group('confirmacionPendiente se limpia al parar externamente', () {
    test('_cargarAlarmas limpia confirmacionPendiente en alarma vencida', () async {
      final a = _alarmaSimple(id: 1, activa: true, diasSemana: []);
      a.confirmacionPendiente = true;
      a.hora = DateTime(2020, 1, 1, 7, 0); // vencida
      await arrancar(alarmas: [a]);

      expect(presenter.alarmas.first.confirmacionPendiente, isFalse,
          reason: 'Al cargar con hora vencida se debe limpiar confirmacionPendiente');
      expect(presenter.alarmas.first.activa, isFalse);
    });

    test('onAppResumed limpia confirmacionPendiente si alarma ya no suena', () async {
      final a = _alarmaSimple(id: 1, activa: true, diasSemana: []);
      await arrancar(alarmas: [a]);
      alarm.sonandoIds.add(1);
      await presenter.onAppResumed(); // establece _alarmaSonando
      presenter.alarmas.first.confirmacionPendiente = true;
      alarm.sonandoIds.remove(1); // alarma parada externamente

      await presenter.onAppResumed();

      expect(presenter.alarmas.first.confirmacionPendiente, isFalse);
      expect(presenter.alarmas.first.activa, isFalse,
          reason: 'Una sola vez parada externamente durante confirmación debe desactivarse');
    });
  });

  // ── control del timer ──────────────────────────────────────────────────────

  group('control del timer', () {
    test('pausarTimer detiene el timer', () async {
      await arrancar();
      expect(presenter.timerActivo, isTrue);
      presenter.pausarTimer();
      expect(presenter.timerActivo, isFalse);
    });

    test('reanudarTimer reactiva el timer', () async {
      await arrancar();
      presenter.pausarTimer();
      expect(presenter.timerActivo, isFalse);
      presenter.reanudarTimer();
      expect(presenter.timerActivo, isTrue);
    });

    test('reanudarTimer durante iniciar() no deja un timer huérfano', () async {
      storage.precargar([]);
      presenter = AlarmasPresenter(
        view: view,
        alarmService: alarm,
        storageService: storage,
        permissionService: FakePermissionService(),
        recordatorioService: recordatorio,
        registro: eventosLog.add,
      );

      // iniciar() aún está en vuelo: simula el resume de un diálogo de permisos.
      final arranque = presenter.iniciar();
      presenter.reanudarTimer();
      await arranque;

      presenter.pausarTimer();
      final congelado = presenter.ahoraNotifier.value;
      await Future<void>.delayed(const Duration(milliseconds: 1200));

      expect(presenter.ahoraNotifier.value, congelado,
          reason: 'Un timer huérfano seguiría actualizando el reloj tras pausar');
    });

    test('reanudarTimer refresca ahoraNotifier inmediatamente', () async {
      await arrancar();
      presenter.pausarTimer();
      final antes = presenter.ahoraNotifier.value;
      await Future.delayed(const Duration(milliseconds: 15));
      presenter.reanudarTimer();
      expect(presenter.ahoraNotifier.value.isAfter(antes), isTrue);
    });

    test('reanudarTimer no crea doble timer', () async {
      await arrancar();
      presenter.reanudarTimer();
      presenter.reanudarTimer();
      expect(presenter.timerActivo, isTrue);
    });
  });

  // ── cobertura del log de diagnóstico ───────────────────────────────────────

  group('cobertura del log', () {
    bool logContiene(String fragmento) =>
        eventosLog.any((e) => e.toLowerCase().contains(fragmento.toLowerCase()));

    test('toggle registra activación y desactivación', () async {
      await arrancar(alarmas: [_alarmaSimple(id: 1, activa: true)]);

      await presenter.toggleAlarma(presenter.alarmas.first, false);
      expect(logContiene('desactivada'), isTrue);

      await presenter.toggleAlarma(presenter.alarmas.first, true);
      expect(logContiene('activada'), isTrue);
    });

    test('eliminar registra el evento', () async {
      await arrancar(alarmas: [_alarmaSimple(id: 1)]);
      await presenter.eliminarAlarma(presenter.alarmas.first);
      expect(logContiene('eliminada'), isTrue);
    });

    test('restaurar (deshacer) registra el evento', () async {
      await arrancar();
      await presenter.restaurarAlarma(_alarmaSimple(id: 1));
      expect(logContiene('restaurada'), isTrue);
    });

    test('editar registra el evento', () async {
      await arrancar(alarmas: [_alarmaSimple(id: 1)]);
      await presenter.actualizarAlarmaCompleta(
        alarma: presenter.alarmas.first,
        nuevaHora: 9,
        nuevoMinuto: 15,
      );
      expect(logContiene('editada'), isTrue);
    });

    test('cerrar con confirmación registra el re-sonido de 30s', () async {
      await arrancar(alarmas: [_alarmaSimple(id: 1)]);
      await presenter.cerrarConConfirmacion(presenter.alarmas.first);
      expect(logContiene('confirmar despertar'), isTrue);
    });
  });

  // ── aviso de full-screen intent ────────────────────────────────────────────

  group('aviso full-screen intent', () {
    test('avisa a la vista si el full-screen intent está denegado', () async {
      storage.precargar(const []);
      final permisos = FakePermissionService()
        ..fullScreenIntentConcedido = false;
      presenter = AlarmasPresenter(
        view: view,
        alarmService: alarm,
        storageService: storage,
        permissionService: permisos,
        recordatorioService: recordatorio,
        registro: eventosLog.add,
      );
      await presenter.iniciar();

      expect(view.fullScreenDenegado, isTrue);
    });

    test('no avisa si el full-screen intent está concedido', () async {
      await arrancar();
      expect(view.fullScreenDenegado, isFalse);
    });
  });

  // ── dispose ────────────────────────────────────────────────────────────────

  group('dispose', () {
    test('se puede llamar sin errores', () async {
      await arrancar();
      expect(() => presenter.dispose(), returnsNormally);
    });
  });

  // ── rutas de alarma no apiladas ────────────────────────────────────────────

  group('rutas de alarma', () {
    test('el banner de foreground impide que onAppResumed apile otra pantalla',
        () async {
      await arrancar(alarmas: [_alarmaSimple(id: 1, diasSemana: [1, 2, 3, 4, 5])]);
      alarm.sonandoIds.add(1);

      alarm.ringingController.add(AlarmSet([_settingsDummy(1)]));
      await Future<void>.delayed(Duration.zero);

      expect(view.ultimaAlarmaForeground, isNotNull,
          reason: 'Con la app visible debe mostrarse el banner');
      view.ultimaAlarmaRinging = null;

      await presenter.onAppResumed();

      expect(view.ultimaAlarmaRinging, isNull,
          reason: 'La alerta ya está en pantalla: no debe empujarse otra ruta');
    });

    test('mostrarPantallaAlarmaDesdeBanner abre la pantalla una sola vez', () async {
      await arrancar(alarmas: [_alarmaSimple(id: 1, diasSemana: [1, 2, 3, 4, 5])]);
      alarm.sonandoIds.add(1);

      presenter.mostrarPantallaAlarmaDesdeBanner(presenter.alarmas.first);
      expect(view.ultimaAlarmaRinging, isNotNull);

      view.ultimaAlarmaRinging = null;
      await presenter.onAppResumed();

      expect(view.ultimaAlarmaRinging, isNull,
          reason: 'Tras abrir desde el banner no debe apilarse una segunda ruta');
    });
  });

  // ── auditoría al volver a primer plano ─────────────────────────────────────

  group('auditoría en onAppResumed', () {
    test('reprograma una alarma que el sistema perdió', () async {
      await arrancar(alarmas: [_alarmaSimple(id: 4, diasSemana: [1, 2, 3, 4, 5])]);

      // El sistema ya no tiene la alarma (reinicio, OEM, force stop).
      alarm.alarmasNativas = [];
      alarm.programadas.clear();
      recordatorio.programados.clear();

      await presenter.onAppResumed();

      expect(alarm.programadas.map((a) => a.id), contains(4));
      expect(recordatorio.programados, contains(4));
      expect(eventosLog.any((l) => l.contains('FALTABAN')), isTrue);
    });

    test('no toca nada si todas las alarmas siguen programadas', () async {
      await arrancar(alarmas: [_alarmaSimple(id: 5, diasSemana: [1, 2, 3, 4, 5])]);

      alarm.alarmasNativas = [_settingsDummy(5)];
      alarm.programadas.clear();
      alarm.detenidas.clear();

      await presenter.onAppResumed();

      expect(alarm.programadas, isEmpty,
          reason: 'No debe reprogramarse lo que ya está en el sistema');
      expect(alarm.detenidas, isEmpty);
    });

    test('no audita mientras una alarma está sonando', () async {
      await arrancar(alarmas: [_alarmaSimple(id: 6, diasSemana: [])]);
      alarm.sonandoIds.add(6);
      alarm.alarmasNativas = [];
      alarm.detenidas.clear();
      final horaAntes = presenter.alarmas.first.hora;

      await presenter.onAppResumed();

      expect(alarm.detenidas, isEmpty,
          reason: 'Auditar con una alarma sonando podría silenciarla');
      expect(presenter.alarmas.first.hora, horaAntes,
          reason: 'Tampoco debe normalizarse su hora mientras suena');
    });

    test('repara una alarma recurrente activa y vencida que el sistema perdió',
        () async {
      await arrancar(alarmas: [_alarmaSimple(id: 7, diasSemana: [1, 2, 3, 4, 5])]);

      // Simular que pasó el tiempo: la hora programada ya venció y, mientras
      // tanto, el sistema perdió la alarma (OEM canceló su AlarmManager).
      presenter.alarmas.first.hora = DateTime(2020, 1, 1, 7, 0);
      alarm.alarmasNativas = [];
      alarm.programadas.clear();
      recordatorio.programados.clear();

      await presenter.onAppResumed();

      expect(presenter.alarmas.first.hora.isAfter(DateTime.now()), isTrue,
          reason: 'Debe recalcular una hora futura, no quedar con la vencida');
      expect(alarm.programadas.map((a) => a.id), contains(7));
      expect(recordatorio.programados, contains(7));
    });

    test('desactiva una alarma de una sola vez vencida que el sistema perdió',
        () async {
      await arrancar(alarmas: [_alarmaSimple(id: 8, diasSemana: [])]);

      presenter.alarmas.first.hora = DateTime(2020, 1, 1, 7, 0);
      alarm.alarmasNativas = [];
      alarm.programadas.clear();
      recordatorio.programados.clear();

      await presenter.onAppResumed();

      expect(presenter.alarmas.first.activa, isFalse,
          reason:
              'Una alarma de una sola vez vencida debe desactivarse, no reprogramarse');
      expect(alarm.programadas.where((a) => a.id == 8), isEmpty);
    });
  });

  // ── guía de Inicio automático (OEM agresivos) ──────────────────────────────

  group('Inicio automático OEM', () {
    test('se recomienda en fabricante agresivo sin atender', () async {
      final permisos = FakePermissionService()..fabricanteAgresivo = true;
      storage.precargar([]);
      presenter = AlarmasPresenter(
        view: view,
        alarmService: alarm,
        storageService: storage,
        permissionService: permisos,
        recordatorioService: recordatorio,
        registro: eventosLog.add,
      );
      await presenter.iniciar();

      expect(view.autostartRecomendado, isTrue);
    });

    test('no se recomienda si ya se atendió', () async {
      final permisos = FakePermissionService()..fabricanteAgresivo = true;
      storage.precargar([]);
      await storage.guardarAutostartAtendido();
      presenter = AlarmasPresenter(
        view: view,
        alarmService: alarm,
        storageService: storage,
        permissionService: permisos,
        recordatorioService: recordatorio,
        registro: eventosLog.add,
      );
      await presenter.iniciar();

      expect(view.autostartRecomendado, isFalse);
    });

    test('no se recomienda en fabricantes no agresivos', () async {
      await arrancar();
      expect(view.autostartRecomendado, isFalse);
    });

    test('abrirAutostart marca el aviso como atendido', () async {
      final permisos = FakePermissionService()..fabricanteAgresivo = true;
      storage.precargar([]);
      presenter = AlarmasPresenter(
        view: view,
        alarmService: alarm,
        storageService: storage,
        permissionService: permisos,
        recordatorioService: recordatorio,
        registro: eventosLog.add,
      );
      await presenter.iniciar();

      await presenter.abrirAutostart();

      expect(view.autostartRecomendado, isFalse);
      expect(await storage.cargarAutostartAtendido(), isTrue);
    });
  });

  // ── iniciar() tolera errores en el bloque de permisos/diagnóstico ─────────

  group('iniciar() tolera errores en el bloque de permisos/diagnóstico', () {
    test('un fallo en esFabricanteAgresivo no impide arrancar el timer y queda en el log', () async {
      final permisos = FakePermissionService()
        ..lanzarErrorEnFabricanteAgresivo = true;
      storage.precargar([]);
      presenter = AlarmasPresenter(
        view: view,
        alarmService: alarm,
        storageService: storage,
        permissionService: permisos,
        recordatorioService: recordatorio,
        registro: eventosLog.add,
      );

      await presenter.iniciar();

      expect(presenter.timerActivo, isTrue,
          reason: 'El reloj debe arrancar aunque falle una comprobación previa');
      expect(eventosLog.any((l) => l.contains('ERROR durante el arranque')),
          isTrue,
          reason: 'El fallo debe quedar registrado en el log de diagnóstico');
    });

    test('la escucha de Alarm.ringing sigue activa tras ese mismo fallo', () async {
      final permisos = FakePermissionService()
        ..lanzarErrorEnFabricanteAgresivo = true;
      storage.precargar([_alarmaSimple(id: 1, diasSemana: [1, 2, 3, 4, 5])]);
      presenter = AlarmasPresenter(
        view: view,
        alarmService: alarm,
        storageService: storage,
        permissionService: permisos,
        recordatorioService: recordatorio,
        registro: eventosLog.add,
      );

      await presenter.iniciar();

      // Si _iniciarEscuchaRinging() no se llegó a ejecutar, este evento no
      // llegaría a ningún callback de la vista.
      alarm.sonandoIds.add(1);
      alarm.ringingController.add(AlarmSet([_settingsDummy(1)]));
      await Future<void>.delayed(Duration.zero);

      expect(view.ultimaAlarmaForeground, isNotNull,
          reason: 'La suscripción al stream de alarmas debe seguir activa '
              'aunque el bloque de permisos haya fallado');
    });
  });

  // ── arranque en frío con una alarma SONANDO ────────────────────────────────

  group('arranque en frío con una alarma sonando', () {
    // Crea un segundo presenter sobre el MISMO storage y el MISMO servicio de
    // alarmas: simula que el proceso murió y la app se vuelve a abrir.
    Future<void> rearrancar() async {
      presenter.dispose();
      presenter = AlarmasPresenter(
        view: view,
        alarmService: alarm,
        storageService: storage,
        permissionService: FakePermissionService(),
        recordatorioService: recordatorio,
        registro: eventosLog.add,
      );
      await presenter.iniciar();
    }

    test('una alarma RECURRENTE sonando no se reprograma ni se detiene', () async {
      // La alarma sonó a las 06:00 con el proceso muerto; el full-screen intent
      // reabre la app. Su `hora` ya venció pero el audio sigue sonando.
      final a = _alarmaSimple(id: 60, activa: true, diasSemana: [1, 2, 3, 4, 5, 6, 7]);
      a.hora = DateTime(2020, 1, 1, 6, 0);
      alarm.alarmasNativas = [_settingsDummy(60)];
      alarm.sonandoIds.add(60);

      await arrancar(alarmas: [a]);

      expect(alarm.detenidas, isNot(contains(60)),
          reason: 'Detener una alarma que suena mata su audio');
      expect(alarm.programadas.where((p) => p.id == 60), isEmpty,
          reason: 'programar() ejecuta Alarm.set, que empieza por Alarm.stop '
              'sobre el mismo id: eso apaga el foreground service y silencia '
              'la alarma que el usuario todavía no ha atendido');
      expect(presenter.alarmas.first.hora, DateTime(2020, 1, 1, 6, 0),
          reason: 'Tampoco debe normalizarse su hora mientras suena: de eso '
              'se encarga detenerAlarma cuando el usuario la atienda');
    });

    test('una alarma de UNA SOLA VEZ sonando no se reprograma ni se detiene',
        () async {
      final a = _alarmaSimple(id: 61, activa: true, diasSemana: []);
      a.hora = DateTime(2020, 1, 1, 6, 0);
      alarm.alarmasNativas = [_settingsDummy(61)];
      alarm.sonandoIds.add(61);

      await arrancar(alarmas: [a]);

      expect(alarm.detenidas, isNot(contains(61)));
      expect(alarm.programadas.where((p) => p.id == 61), isEmpty);
      expect(presenter.alarmas.first.activa, isTrue,
          reason: 'Mientras suena no se normaliza: desactivarla y persistirlo '
              'la convierte en huérfana para el siguiente arranque');
    });

    test('una alarma de UNA SOLA VEZ sigue a salvo en un SEGUNDO arranque en frío',
        () async {
      final a = _alarmaSimple(id: 62, activa: true, diasSemana: []);
      a.hora = DateTime(2020, 1, 1, 6, 0);
      alarm.alarmasNativas = [_settingsDummy(62)];
      alarm.sonandoIds.add(62);

      await arrancar(alarmas: [a]);
      expect(alarm.detenidas, isNot(contains(62)));

      // MIUI relanza la activity (o el usuario quita la app de Recientes y
      // toca la notificación): el proceso arranca otra vez y la alarma SIGUE
      // sonando, porque androidStopAlarmOnTermination es false.
      await rearrancar();

      expect(alarm.detenidas, isNot(contains(62)),
          reason: 'En el segundo arranque la alarma ya no figura como activa '
              'en storage; sin la protección de "está sonando ahora" la '
              'auditoría la clasificaría como huérfana y la silenciaría');
      expect(alarm.programadas.where((p) => p.id == 62), isEmpty);
    });

    test('la alarma que ya sonaba al arrancar abre la PANTALLA COMPLETA, no el banner',
        () async {
      // Camino principal del escenario que motiva toda la rama: el
      // full-screen intent abre la Activity POR la alarma. `Alarm.init()` →
      // `checkAlarm()` siembra el BehaviorSubject de `ringing` con la alarma
      // que ya suena, así que _iniciarEscuchaRinging() recibe ese valor nada
      // más suscribirse — con el ciclo de vida ya en `resumed`, porque la
      // Activity acaba de abrirse.
      final a = _alarmaSimple(id: 65, activa: true, diasSemana: [1, 2, 3, 4, 5, 6, 7]);
      a.hora = DateTime(2020, 1, 1, 6, 0);
      alarm.alarmasNativas = [_settingsDummy(65)];
      alarm.sonandoIds.add(65);

      await arrancar(alarmas: [a]);

      alarm.ringingController.add(AlarmSet([_settingsDummy(65)]));
      await Future<void>.delayed(Duration.zero);

      expect(view.ultimaAlarmaRinging, isNotNull,
          reason: 'La app se abrió POR la alarma: debe verse '
              'PantallaAlarmaActiva con su deslizamiento, no un aviso pequeño');
      expect(view.ultimaAlarmaForeground, isNull,
          reason: 'El banner es solo para cuando la alarma suena con la app ya '
              'en uso');
    });

    test('tras atenderla, un nuevo disparo con la app en uso vuelve al banner',
        () async {
      // La marca "ya sonaba al arrancar" se consume: el re-sonido de la
      // confirmación de despertar ocurre con la persona mirando la app.
      final a = _alarmaSimple(id: 66, activa: true, diasSemana: [1, 2, 3, 4, 5, 6, 7]);
      a.hora = DateTime(2020, 1, 1, 6, 0);
      alarm.alarmasNativas = [_settingsDummy(66)];
      alarm.sonandoIds.add(66);

      await arrancar(alarmas: [a]);
      alarm.ringingController.add(AlarmSet([_settingsDummy(66)]));
      await Future<void>.delayed(Duration.zero);
      expect(view.ultimaAlarmaRinging, isNotNull);

      // El usuario la atiende y la alarma vuelve a sonar más tarde.
      await presenter.detenerAlarma(presenter.alarmas.first);
      alarm.ringingController.add(AlarmSet.empty());
      await Future<void>.delayed(Duration.zero);
      alarm.sonandoIds.add(66);
      alarm.ringingController.add(AlarmSet([_settingsDummy(66)]));
      await Future<void>.delayed(Duration.zero);

      expect(view.ultimaAlarmaForeground, isNotNull,
          reason: 'Con la app en uso el aviso correcto es el banner');
    });

    test('una alarma que NO suena sí se reprograma en el mismo arranque', () async {
      final sonando = _alarmaSimple(id: 63, activa: true, diasSemana: [1, 2, 3, 4, 5, 6, 7]);
      sonando.hora = DateTime(2020, 1, 1, 6, 0);
      final normal = _alarmaSimple(id: 64, activa: true, diasSemana: [1, 2, 3, 4, 5, 6, 7]);
      normal.hora = DateTime(2020, 1, 1, 7, 0);
      alarm.alarmasNativas = [_settingsDummy(63)];
      alarm.sonandoIds.add(63);

      await arrancar(alarmas: [sonando, normal]);

      expect(alarm.programadas.map((p) => p.id), contains(64),
          reason: 'Saltarse la que suena no debe saltarse las demás');
    });
  });

  // ── un programar() roto no debe arrastrar a las demás ──────────────────────

  group('tolerancia a fallos al programar', () {
    test('un fallo al cargar no impide programar el resto de alarmas', () async {
      final rota = _alarmaSimple(id: 70, diasSemana: [1, 2, 3, 4, 5]);
      final sana = _alarmaSimple(id: 71, diasSemana: [1, 2, 3, 4, 5]);
      rota.hora = DateTime.now().add(const Duration(hours: 1));
      sana.hora = DateTime.now().add(const Duration(hours: 2));
      alarm.idsQueFallanAlProgramar.add(70);

      await arrancar(alarmas: [rota, sana]);

      expect(alarm.programadas.map((p) => p.id), contains(71),
          reason: 'La alarma #70 lanza; sin try/catch por alarma, la #71 '
              'nunca llegaría a programarse');
      expect(eventosLog.any((l) => l.contains('#70')), isTrue,
          reason: 'El fallo debe quedar registrado en el diagnóstico');
    });

    test('un fallo en la auditoría no impide reparar el resto', () async {
      final rota = _alarmaSimple(id: 72, diasSemana: [1, 2, 3, 4, 5]);
      final sana = _alarmaSimple(id: 73, diasSemana: [1, 2, 3, 4, 5]);
      rota.hora = DateTime.now().add(const Duration(hours: 1));
      sana.hora = DateTime.now().add(const Duration(hours: 2));
      await arrancar(alarmas: [rota, sana]);

      // El sistema perdió ambas y la #72 falla al reprogramarse.
      alarm.alarmasNativas = [];
      alarm.programadas.clear();
      alarm.idsQueFallanAlProgramar.add(72);

      await presenter.onAppResumed();

      expect(alarm.programadas.map((p) => p.id), contains(73),
          reason: 'Sin try/catch por alarma la excepción escapa de '
              'onAppResumed como error de Future no capturado');
    });
  });

  // ── reentrada de onAppResumed ──────────────────────────────────────────────

  group('reentrada de onAppResumed', () {
    // Cada ejecución de _auditarAlarmasProgramadas deja exactamente una línea
    // "Auditoría:" en el log, así que contarlas cuenta auditorías reales.
    int auditorias() =>
        eventosLog.where((e) => e.contains('Auditoría')).length;

    test('un resume durante iniciar() no audita a medias', () async {
      final permisos = FakePermissionService()..exentoBateria = false;
      storage.precargar([_alarmaSimple(id: 80, diasSemana: [1, 2, 3, 4, 5])]);
      presenter = AlarmasPresenter(
        view: view,
        alarmService: alarm,
        storageService: storage,
        permissionService: permisos,
        recordatorioService: recordatorio,
        registro: eventosLog.add,
      );
      int? auditoriasDuranteIniciar;
      // El diálogo del sistema de exención de batería se cierra y llega
      // `resumed` mientras iniciar() sigue en vuelo.
      permisos.alSolicitarExencionBateria = () async {
        await presenter.onAppResumed();
        auditoriasDuranteIniciar = auditorias();
      };

      await presenter.iniciar();

      expect(auditoriasDuranteIniciar, 1,
          reason: 'Mientras iniciar() sigue en vuelo solo debe haber auditado '
              '_cargarAlarmas; un onAppResumed reentrante auditaría por '
              'segunda vez sobre un estado a medio construir, con el mismo '
              'riesgo de cancelar como huérfana una alarma que está sonando');
      expect(auditorias(), 2,
          reason: 'El resume no se descarta: se difiere y se procesa (y por '
              'tanto audita) cuando iniciar() ya ha terminado');
    });

    test('un resume durante iniciar() queda PENDIENTE y se procesa al terminar',
        () async {
      // Regresión crítica: con el resume descartado, el `.then()` que la vista
      // encadena a onAppResumed corría igual con hayAlarmaSonando == false y
      // el App Open Ad podía aparecer ENCIMA de la alarma sonando. Ventana
      // real: la persona denegó la exención de batería, así que iniciar() abre
      // ese diálogo del sistema (otra Activity → paused → resumed).
      final permisos = FakePermissionService()..exentoBateria = false;
      storage.precargar([_alarmaSimple(id: 82, diasSemana: [1, 2, 3, 4, 5])]);
      presenter = AlarmasPresenter(
        view: view,
        alarmService: alarm,
        storageService: storage,
        permissionService: permisos,
        recordatorioService: recordatorio,
        registro: eventosLog.add,
      );
      bool? pendienteJustoDespues;
      permisos.alSolicitarExencionBateria = () async {
        // Al cerrar el diálogo la alarma ya está sonando.
        alarm.sonandoIds.add(82);
        await presenter.onAppResumed();
        pendienteJustoDespues = presenter.resumePendiente;
      };

      await presenter.iniciar();

      expect(pendienteJustoDespues, isTrue,
          reason: 'Es la señal que consulta la vista: mientras el resume esté '
              'sin procesar no puede decidir el anuncio, porque '
              'hayAlarmaSonando todavía no significa nada');
      expect(presenter.resumePendiente, isFalse,
          reason: 'Al terminar iniciar() el resume diferido ya se procesó');
      expect(presenter.hayAlarmaSonando, isTrue,
          reason: 'El resume diferido debe detectar la alarma con '
              'alarmIsRinging, igual que si hubiera llegado más tarde');
      expect(view.ultimaAlarmaRinging, isNotNull,
          reason: 'Y mostrar su pantalla completa');
    });

    test('dos onAppResumed simultáneos auditan una sola vez', () async {
      await arrancar(alarmas: [_alarmaSimple(id: 81, diasSemana: [1, 2, 3, 4, 5])]);
      final antes = auditorias();

      await Future.wait([presenter.onAppResumed(), presenter.onAppResumed()]);

      expect(auditorias(), antes + 1,
          reason: 'La guardia de reentrada debe descartar el segundo resume');
    });
  });

  // ── Inicio automático: el aviso solo se atiende si se abrió de verdad ──────

  group('Inicio automático — aviso atendido', () {
    Future<FakePermissionService> arrancarConAutostart({
      required bool seAbre,
    }) async {
      final permisos = FakePermissionService()
        ..fabricanteAgresivo = true
        ..autostartSeAbre = seAbre;
      storage.precargar([]);
      presenter = AlarmasPresenter(
        view: view,
        alarmService: alarm,
        storageService: storage,
        permissionService: permisos,
        recordatorioService: recordatorio,
        registro: eventosLog.add,
      );
      await presenter.iniciar();
      return permisos;
    }

    test('si no se abrió ninguna pantalla del fabricante el aviso sigue vivo',
        () async {
      await arrancarConAutostart(seAbre: false);
      expect(view.autostartRecomendado, isTrue);

      await presenter.abrirAutostart();

      expect(await storage.cargarAutostartAtendido(), isFalse,
          reason: 'Sin pantalla del fabricante el usuario no pudo activar '
              'nada: dar el aviso por atendido elimina en silencio la única '
              'mitigación de la causa raíz');
      expect(view.autostartRecomendado, isTrue,
          reason: 'El banner debe seguir visible para reintentarlo');
    });

    test('si se abrió la pantalla del fabricante el aviso queda atendido',
        () async {
      await arrancarConAutostart(seAbre: true);

      await presenter.abrirAutostart();

      expect(await storage.cargarAutostartAtendido(), isTrue);
      expect(view.autostartRecomendado, isFalse);
    });
  });
}
