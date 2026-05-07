import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:despertador_novia/models/alarma.dart';
import 'package:despertador_novia/services/storage_service.dart';
import 'package:despertador_novia/utils/constantes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  final storage = StorageService();

  group('StorageService — guardar y cargar', () {
    test('lista vacía se guarda y carga correctamente', () async {
      await storage.guardarAlarmas([], 1);
      final resultado = await storage.cargarAlarmas();

      expect(resultado.alarmas, isEmpty);
      expect(resultado.nextId, 1);
    });

    test('una alarma completa hace round-trip sin pérdida de datos', () async {
      final original = Alarma(
        id: 5,
        hora: DateTime(2026, 7, 15, 9, 30),
        etiqueta: 'Trabajo',
        activa: true,
        pospuesta: false,
        diasSemana: [1, 2, 3, 4, 5],
        horaDelDia: 9,
        minutoDelDia: 30,
      );

      await storage.guardarAlarmas([original], 6);
      final resultado = await storage.cargarAlarmas();

      expect(resultado.nextId, 6);
      expect(resultado.alarmas, hasLength(1));
      final cargada = resultado.alarmas.first;
      expect(cargada.id, original.id);
      expect(cargada.hora, original.hora);
      expect(cargada.etiqueta, original.etiqueta);
      expect(cargada.activa, original.activa);
      expect(cargada.pospuesta, original.pospuesta);
      expect(cargada.diasSemana, original.diasSemana);
      expect(cargada.horaDelDia, original.horaDelDia);
      expect(cargada.minutoDelDia, original.minutoDelDia);
    });

    test('múltiples alarmas se guardan y cargan en orden', () async {
      final alarmas = [
        Alarma(id: 1, hora: DateTime(2026, 1, 1, 6, 0), etiqueta: 'A'),
        Alarma(id: 2, hora: DateTime(2026, 1, 1, 8, 0), etiqueta: 'B'),
        Alarma(id: 3, hora: DateTime(2026, 1, 1, 10, 0), etiqueta: 'C'),
      ];

      await storage.guardarAlarmas(alarmas, 4);
      final resultado = await storage.cargarAlarmas();

      expect(resultado.alarmas, hasLength(3));
      expect(resultado.alarmas.map((a) => a.id).toList(), [1, 2, 3]);
    });

    test('nextId se infiere correctamente cuando falta la clave', () async {
      // Guardar manualmente sin nextId
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(claveAlarmas, [
        '{"id":3,"hora":"2026-01-01T07:00:00.000","etiqueta":"X","activa":true,"pospuesta":false,"diasSemana":[],"horaDelDia":7,"minutoDelDia":0}',
        '{"id":7,"hora":"2026-01-01T08:00:00.000","etiqueta":"Y","activa":true,"pospuesta":false,"diasSemana":[],"horaDelDia":8,"minutoDelDia":0}',
      ]);

      final resultado = await storage.cargarAlarmas();
      expect(resultado.nextId, 8, reason: 'nextId debe ser max(ids) + 1 = 7+1');
    });
  });

  group('StorageService — resistencia a datos corruptos', () {
    test('una entrada corrompida no rompe la carga de las demás', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(claveAlarmas, [
        '{"id":1,"hora":"2026-01-01T07:00:00.000","etiqueta":"Buena","activa":true,"pospuesta":false,"diasSemana":[],"horaDelDia":7,"minutoDelDia":0}',
        'ESTO_NO_ES_JSON_VALIDO{{{{',
        '{"id":2,"hora":"2026-01-01T08:00:00.000","etiqueta":"Otra buena","activa":true,"pospuesta":false,"diasSemana":[],"horaDelDia":8,"minutoDelDia":0}',
      ]);

      final resultado = await storage.cargarAlarmas();

      expect(resultado.alarmas, hasLength(2),
          reason: 'Solo las entradas válidas deben cargarse');
      expect(resultado.alarmas.map((a) => a.id).toList(), containsAll([1, 2]));
    });

    test('todas las entradas corruptas devuelve lista vacía', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(claveAlarmas, [
        'null',
        '{invalid}',
        '[]',
      ]);

      final resultado = await storage.cargarAlarmas();
      expect(resultado.alarmas, isEmpty);
    });

    test('sin datos guardados devuelve lista vacía y nextId=1', () async {
      final resultado = await storage.cargarAlarmas();
      expect(resultado.alarmas, isEmpty);
      expect(resultado.nextId, 1);
    });

    test('alarma con horaDelDia/minutoDelDia ausentes usa fallback de hora', () async {
      final prefs = await SharedPreferences.getInstance();
      // JSON sin horaDelDia ni minutoDelDia (datos viejos antes de la migración)
      await prefs.setStringList(claveAlarmas, [
        '{"id":1,"hora":"2026-01-01T14:30:00.000","etiqueta":"Vieja","activa":true,"pospuesta":false,"diasSemana":[]}',
      ]);

      final resultado = await storage.cargarAlarmas();
      expect(resultado.alarmas, hasLength(1));
      final alarma = resultado.alarmas.first;
      expect(alarma.horaDelDia, 14, reason: 'Fallback a hora.hour');
      expect(alarma.minutoDelDia, 30, reason: 'Fallback a hora.minute');
    });
  });

  group('StorageService — sobrescritura', () {
    test('guardar dos veces no duplica alarmas', () async {
      final alarma = Alarma(id: 1, hora: DateTime(2026, 1, 1, 7, 0), etiqueta: 'Única');

      await storage.guardarAlarmas([alarma], 2);
      await storage.guardarAlarmas([alarma], 2);
      final resultado = await storage.cargarAlarmas();

      expect(resultado.alarmas, hasLength(1));
    });
  });
}
