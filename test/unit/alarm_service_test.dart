import 'package:flutter_test/flutter_test.dart';

import 'package:despertador_novia/models/alarma.dart';
import 'package:despertador_novia/services/alarm_service.dart';

/// Tests de la lógica de AlarmService que NO depende del binding nativo del
/// package `alarm` (los caminos que retornan antes de llamar a Alarm.set).
/// Verifican que los recordatorios omitidos quedan registrados en el log.
void main() {
  test('programarRecordatorio registra OMITIDO si la alarma está pospuesta',
      () async {
    final logs = <String>[];
    final service = AlarmService(registro: logs.add);
    final alarma = Alarma(
      id: 1,
      hora: DateTime.now().add(const Duration(hours: 2)),
      etiqueta: 'Test',
      pospuesta: true,
    );

    await service.programarRecordatorio(alarma);

    expect(
      logs.any((l) =>
          l.contains('OMITIDO') && l.toLowerCase().contains('pospuesta')),
      isTrue,
    );
  });

  test('programarRecordatorio registra OMITIDO si faltan menos de 30 min',
      () async {
    final logs = <String>[];
    final service = AlarmService(registro: logs.add);
    final alarma = Alarma(
      id: 2,
      hora: DateTime.now().add(const Duration(minutes: 10)),
      etiqueta: 'Test',
    );

    await service.programarRecordatorio(alarma);

    expect(logs.any((l) => l.contains('OMITIDO')), isTrue);
  });
}
