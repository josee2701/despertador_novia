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
