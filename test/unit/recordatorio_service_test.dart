import 'package:flutter_test/flutter_test.dart';

import 'package:despertador_novia/models/alarma.dart';
import 'package:despertador_novia/services/recordatorio_service.dart';

import 'dobles_notificaciones.dart';

Alarma _alarma({
  int id = 1,
  Duration falta = const Duration(hours: 2),
  bool pospuesta = false,
}) {
  final cuando = DateTime.now().add(falta);
  return Alarma(
    id: id,
    hora: cuando,
    etiqueta: 'Despertar',
    pospuesta: pospuesta,
    horaDelDia: 6,
    minutoDelDia: 30,
  );
}

void main() {
  late PlanificadorFalso planificador;
  late List<String> logs;
  late RecordatorioService servicio;

  setUp(() {
    planificador = PlanificadorFalso();
    logs = [];
    servicio = RecordatorioService(
      planificador: planificador,
      registro: logs.add,
    );
  });

  test('programa la notificación 30 minutos antes del disparo', () async {
    final alarma = _alarma(falta: const Duration(hours: 2));

    await servicio.programar(alarma);

    final id = alarma.id + RecordatorioService.offsetNotificacion;
    expect(planificador.programados, contains(id));
    expect(
      planificador.programados[id],
      alarma.hora.subtract(RecordatorioService.antelacion),
    );
    expect(logs.any((l) => l.contains('programado')), isTrue);
  });

  test('el cuerpo usa la hora configurada, no la del snooze', () async {
    final alarma = _alarma(falta: const Duration(hours: 2));

    await servicio.programar(alarma);

    final id = alarma.id + RecordatorioService.offsetNotificacion;
    expect(planificador.cuerpos[id], contains('Despertar'));
    expect(planificador.cuerpos[id], contains('30 minutos'));
  });

  test('omite y registra si la alarma está pospuesta', () async {
    await servicio.programar(_alarma(pospuesta: true));

    expect(planificador.programados, isEmpty);
    expect(
      logs.any((l) =>
          l.contains('OMITIDO') && l.toLowerCase().contains('pospuesta')),
      isTrue,
    );
  });

  test('omite y registra si faltan menos de 30 minutos', () async {
    await servicio.programar(_alarma(falta: const Duration(minutes: 10)));

    expect(planificador.programados, isEmpty);
    expect(logs.any((l) => l.contains('OMITIDO')), isTrue);
  });

  test('al omitir por snooze retira el recordatorio con la hora vieja', () async {
    // El recordatorio de las 06:30 ya está puesto. La persona pospone: la
    // alarma pasa a sonar en 5 minutos y programar() OMITE. Sin retirar el
    // anterior, a las 06:30 salta un aviso que miente ("suena en 30 minutos")
    // sobre una alarma que ya sonó.
    final alarma = _alarma(id: 4, falta: const Duration(hours: 2));
    await servicio.programar(alarma);
    expect(planificador.programados,
        contains(4 + RecordatorioService.offsetNotificacion));

    alarma.pospuesta = true;
    await servicio.programar(alarma);

    expect(planificador.programados,
        isNot(contains(4 + RecordatorioService.offsetNotificacion)),
        reason: 'Si no se programa uno nuevo, el viejo no puede sobrevivir');
  });

  test('al omitir por falta de tiempo retira el recordatorio con la hora vieja',
      () async {
    // Mismo caso por la otra vía: la alarma se edita a una hora que está a
    // menos de 30 minutos. zonedSchedule reemplaza por ID, pero aquí no llega
    // a llamarse, así que la retirada tiene que ser explícita.
    final alarma = _alarma(id: 5, falta: const Duration(hours: 2));
    await servicio.programar(alarma);

    alarma.hora = DateTime.now().add(const Duration(minutes: 10));
    await servicio.programar(alarma);

    expect(planificador.programados,
        isNot(contains(5 + RecordatorioService.offsetNotificacion)),
        reason: 'El aviso de la hora anterior debe desaparecer');
  });

  test('cancelar borra la notificación del ID desplazado', () async {
    final alarma = _alarma(id: 7);
    await servicio.programar(alarma);

    await servicio.cancelar(7);

    expect(planificador.cancelados,
        contains(7 + RecordatorioService.offsetNotificacion));
    expect(planificador.programados, isEmpty);
  });

  test('un fallo del planificador se registra y no propaga', () async {
    planificador.fallar = true;

    await servicio.programar(_alarma());
    await servicio.cancelar(1);

    expect(logs.where((l) => l.contains('ERROR')).length, 2);
  });
}
