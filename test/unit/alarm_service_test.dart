import 'package:despertador_novia/models/alarma.dart';
import 'package:despertador_novia/services/alarm_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('crearConfiguracion: sin stopButton y con ajustes de fiabilidad', () {
    final alarma = Alarma(
      id: 1,
      hora: DateTime(2030, 1, 1, 7, 0),
      etiqueta: 'Test',
    );
    final c = AlarmService(registro: (_) {}).crearConfiguracion(alarma);
    expect(c.notificationSettings.stopButton, isNull);
    expect(c.androidStopAlarmOnTermination, isFalse);
    expect(c.loopAudio, isTrue);
    expect(c.androidFullScreenIntent, isTrue);
  });
}
