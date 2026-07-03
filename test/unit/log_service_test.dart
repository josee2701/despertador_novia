import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:despertador_novia/services/log_service.dart';

/// Tests del LogService usando un archivo temporal real (dart:io), sin depender
/// de path_provider. Se prueba la escritura y, sobre todo, que el recorte NO se
/// haga en cada escritura (eficiencia) sino por lotes al superar el umbral.
void main() {
  late Directory dir;
  late File archivo;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('logtest');
    archivo = File('${dir.path}/diag.log');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('registrar guarda el evento en el archivo', () async {
    final log = LogService.paraPruebas(archivo);

    await log.registrar('Alarma #1 DISPARÓ');

    final contenido = await log.leerLog();
    expect(contenido.contains('Alarma #1 DISPARÓ'), isTrue);
  });

  test('recorta por lotes (no en cada escritura) conservando las recientes',
      () async {
    // maxLineas 5, margen 2 → recorta al superar 7 líneas.
    final log = LogService.paraPruebas(archivo, maxLineas: 5, margenRecorte: 2);

    for (var i = 0; i < 8; i++) {
      await log.registrar('evento $i');
    }

    // Con recorte por lotes debe recortar como mucho una vez, no 8 veces.
    expect(log.recortesRealizados, lessThanOrEqualTo(1));

    final contenido = await log.leerLog();
    expect(contenido.contains('evento 7'), isTrue,
        reason: 'debe conservar los eventos más recientes');
    expect(contenido.contains('evento 0'), isFalse,
        reason: 'debe descartar los eventos más antiguos');
  });

  test('no recorta mientras no se supera el umbral', () async {
    final log = LogService.paraPruebas(archivo, maxLineas: 5, margenRecorte: 2);

    for (var i = 0; i < 5; i++) {
      await log.registrar('evento $i');
    }

    expect(log.recortesRealizados, 0);
    final contenido = await log.leerLog();
    expect(contenido.contains('evento 0'), isTrue);
  });
}
