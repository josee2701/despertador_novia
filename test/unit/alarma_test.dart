import 'package:flutter_test/flutter_test.dart';
import 'package:despertador_novia/models/alarma.dart';

void main() {
  group('Alarma', () {
    test('constructor con valores por defecto', () {
      final alarma = Alarma(
        id: 1,
        hora: DateTime(2026, 5, 4, 7, 0),
        etiqueta: 'Despertar',
      );

      expect(alarma.id, 1);
      expect(alarma.activa, isTrue);
      expect(alarma.pospuesta, isFalse);
      expect(alarma.diasSemana, isEmpty);
    });

    test('constructor con días de semana', () {
      final alarma = Alarma(
        id: 2,
        hora: DateTime(2026, 5, 4, 8, 30),
        etiqueta: 'Trabajo',
        diasSemana: [1, 2, 3, 4, 5],
      );

      expect(alarma.diasSemana, hasLength(5));
      expect(alarma.diasSemana.contains(1), isTrue);
      expect(alarma.diasSemana.contains(6), isFalse);
    });

    test('toJson serializa correctamente', () {
      final alarma = Alarma(
        id: 3,
        hora: DateTime(2026, 5, 4, 14, 15),
        etiqueta: 'Siesta',
        activa: false,
        pospuesta: true,
        diasSemana: [3, 5],
      );

      final json = alarma.toJson();

      expect(json['id'], 3);
      expect(json['hora'], '2026-05-04T14:15:00.000');
      expect(json['etiqueta'], 'Siesta');
      expect(json['activa'], isFalse);
      expect(json['pospuesta'], isTrue);
      expect(json['diasSemana'], [3, 5]);
    });

    test('fromJson deserializa correctamente', () {
      final json = {
        'id': 4,
        'hora': '2026-06-10T09:45:00.000',
        'etiqueta': 'Reunión',
        'activa': true,
        'pospuesta': false,
        'diasSemana': [1, 3, 5],
      };

      final alarma = Alarma.fromJson(json);

      expect(alarma.id, 4);
      expect(alarma.hora, DateTime(2026, 6, 10, 9, 45));
      expect(alarma.etiqueta, 'Reunión');
      expect(alarma.activa, isTrue);
      expect(alarma.pospuesta, isFalse);
      expect(alarma.diasSemana, [1, 3, 5]);
    });

    test('fromJson con pospuesta null', () {
      final json = {
        'id': 5,
        'hora': '2026-01-01T00:00:00.000',
        'etiqueta': 'Año Nuevo',
        'activa': true,
        'pospuesta': null,
        'diasSemana': [],
      };

      final alarma = Alarma.fromJson(json);

      expect(alarma.pospuesta, isFalse);
    });

    test('fromJson con diasSemana null', () {
      final json = {
        'id': 6,
        'hora': '2026-01-01T00:00:00.000',
        'etiqueta': 'Test',
        'activa': true,
        'pospuesta': false,
        'diasSemana': null,
      };

      final alarma = Alarma.fromJson(json);

      expect(alarma.diasSemana, isEmpty);
    });

    test('round-trip toJson -> fromJson', () {
      final original = Alarma(
        id: 7,
        hora: DateTime(2026, 12, 25, 6, 30),
        etiqueta: 'Navidad',
        activa: true,
        pospuesta: false,
        diasSemana: [7],
      );

      final restaurada = Alarma.fromJson(original.toJson());

      expect(restaurada.id, original.id);
      expect(restaurada.hora, original.hora);
      expect(restaurada.etiqueta, original.etiqueta);
      expect(restaurada.activa, original.activa);
      expect(restaurada.pospuesta, original.pospuesta);
      expect(restaurada.diasSemana, original.diasSemana);
    });

    group('copyWith', () {
      test('sin parámetros devuelve copia idéntica', () {
        final alarma = Alarma(
          id: 1,
          hora: DateTime(2026, 5, 4, 7, 0),
          etiqueta: 'Original',
          diasSemana: [1, 2],
        );

        final copia = alarma.copyWith();

        expect(copia.id, alarma.id);
        expect(copia.hora, alarma.hora);
        expect(copia.etiqueta, alarma.etiqueta);
        expect(copia.activa, alarma.activa);
        expect(copia.pospuesta, alarma.pospuesta);
        expect(copia.diasSemana, alarma.diasSemana);
        expect(copia.diasSemana == alarma.diasSemana, isFalse); // Copia independiente
      });

      test('modifica solo campos especificados', () {
        final alarma = Alarma(
          id: 1,
          hora: DateTime(2026, 5, 4, 7, 0),
          etiqueta: 'Original',
        );

        final modificada = alarma.copyWith(
          etiqueta: 'Nueva',
          activa: false,
        );

        expect(modificada.id, alarma.id);
        expect(modificada.hora, alarma.hora);
        expect(modificada.etiqueta, 'Nueva');
        expect(modificada.activa, isFalse);
      });
    });

    test('toString contiene información relevante', () {
      final alarma = Alarma(
        id: 42,
        hora: DateTime(2026, 5, 4, 7, 0),
        etiqueta: 'Test',
      );

      final str = alarma.toString();

      expect(str, contains('Alarma'));
      expect(str, contains('42'));
      expect(str, contains('Test'));
    });
  });
}
