import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:despertador_novia/models/alarma.dart';
import 'package:despertador_novia/presenters/alarmas_presenter.dart';
import 'package:despertador_novia/services/alarm_service.dart';
import 'package:despertador_novia/services/permission_service.dart';
import 'package:despertador_novia/services/storage_service.dart';

// ─── Fakes ────────────────────────────────────────────────────────────────────

class FakeAlarmService extends AlarmService {
  final List<Alarma> programadas = [];
  final List<int> detenidas = [];
  final Set<int> sonandoIds = {};
  List<AlarmSettings> alarmasNativas = [];

  /// IDs de recordatorios programados actualmente.
  final Set<int> recordatoriosProgramados = {};

  final StreamController<AlarmSet> ringingController = StreamController<AlarmSet>.broadcast();

  @override
  Future<void> init() async {}

  @override
  Future<void> programar(Alarma alarma) async {
    programadas.removeWhere((a) => a.id == alarma.id);
    programadas.add(alarma.copyWith());
  }

  @override
  Future<void> programarRecordatorio(Alarma alarma) async {
    // Solo registrar si la alarma no está en snooze y el recordatorio es futuro.
    if (alarma.pospuesta) return;
    final momento = alarma.hora.subtract(const Duration(minutes: 30));
    if (!momento.isAfter(DateTime.now())) return;
    recordatoriosProgramados.add(alarma.id + AlarmService.offsetRecordatorio);
  }

  @override
  Future<void> cancelarRecordatorio(int alarmaId) async {
    final idRecordatorio = alarmaId + AlarmService.offsetRecordatorio;
    detenidas.add(idRecordatorio);
    recordatoriosProgramados.remove(idRecordatorio);
  }

  @override
  Future<void> detener(int id) async {
    detenidas.add(id);
    sonandoIds.remove(id);
  }

  @override
  Future<bool> alarmIsRinging(int id) async => sonandoIds.contains(id);

  @override
  Future<List<AlarmSettings>> getAlarmasNativas() async => alarmasNativas;

  @override
  Stream<AlarmSet> get ringingStream => ringingController.stream;
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
}

class FakePermissionService extends PermissionService {
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
  @override
  void onMostrarPantallaAlarma(Alarma alarma) => ultimaAlarmaRinging = alarma;
  @override
  void onAlarmaSonandoEnForeground(Alarma alarma) => ultimaAlarmaForeground = alarma;
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

  setUp(() {
    view = FakeView();
    alarm = FakeAlarmService();
    storage = FakeStorageService();
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

  // ── dispose ────────────────────────────────────────────────────────────────

  group('dispose', () {
    test('se puede llamar sin errores', () async {
      await arrancar();
      expect(() => presenter.dispose(), returnsNormally);
    });
  });

  // ── recordatorios ──────────────────────────────────────────────────────────

  group('recordatorios', () {
    test('agregarAlarma programa recordatorio con ID = alarmaId + offsetRecordatorio', () async {
      await arrancar();
      await presenter.agregarAlarma(
        hora: 23,
        minuto: 59,
        etiqueta: 'Tarde',
        diasSemana: [],
      );
      final id = presenter.alarmas.first.id;
      expect(
        alarm.recordatoriosProgramados,
        contains(id + AlarmService.offsetRecordatorio),
      );
    });

    test('desactivar alarma cancela el recordatorio', () async {
      await arrancar(alarmas: [_alarmaSimple(id: 5, activa: true)]);
      alarm.detenidas.clear();

      await presenter.toggleAlarma(presenter.alarmas.first, false);

      expect(alarm.detenidas, contains(5 + AlarmService.offsetRecordatorio));
    });

    test('actualizarEtiqueta actualiza la etiqueta y reprograma el recordatorio', () async {
      await arrancar(alarmas: [_alarmaSimple(id: 1, activa: true)]);
      alarm.detenidas.clear();

      await presenter.actualizarEtiqueta(presenter.alarmas.first, 'Nueva etiqueta');

      expect(presenter.alarmas.first.etiqueta, 'Nueva etiqueta');
      expect(alarm.detenidas, contains(1 + AlarmService.offsetRecordatorio));
      expect(
        alarm.recordatoriosProgramados,
        contains(1 + AlarmService.offsetRecordatorio),
      );
    });

    test('actualizarEtiqueta con cadena vacía normaliza a "Alarma"', () async {
      await arrancar(alarmas: [_alarmaSimple(id: 1)]);
      await presenter.actualizarEtiqueta(presenter.alarmas.first, '   ');
      expect(presenter.alarmas.first.etiqueta, 'Alarma');
    });
  });
}
