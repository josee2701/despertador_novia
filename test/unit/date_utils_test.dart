import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:despertador_novia/utils/date_utils.dart' as utils;

void main() {
  group('proximaFecha', () {
    test('alarma diaria sin días: mañana si ya pasó hoy', () {
      final resultado = utils.proximaFecha(8, 0, []);
      final esperado = DateTime.now();
      final manana = DateTime(esperado.year, esperado.month, esperado.day + 1, 8, 0);
      expect(resultado, manana);
    });

    test('alarma diaria sin días: hoy si no ha pasado', () {
      final resultado = utils.proximaFecha(23, 59, []);
      final ahora = DateTime.now();
      final esperado = DateTime(ahora.year, ahora.month, ahora.day, 23, 59);
      expect(resultado, esperado);
    });

    test('alarma con días: encuentra un día válido', () {
      final resultado = utils.proximaFecha(8, 0, [1, 3, 5]);
      expect([1, 3, 5], contains(resultado.weekday));
      expect(resultado.hour, 8);
      expect(resultado.minute, 0);
    });

    test('alarma con múltiples días: elige un día válido', () {
      final resultado = utils.proximaFecha(14, 0, [2, 4]);
      expect([2, 4], contains(resultado.weekday));
    });
  });

  group('formatearHoraAMPM', () {
    test('medianoche exacta', () {
      expect(utils.formatearHoraAMPM(DateTime(2026, 1, 1, 0, 0)), '12:00 AM');
    });

    test('mediodía exacto', () {
      expect(utils.formatearHoraAMPM(DateTime(2026, 1, 1, 12, 0)), '12:00 PM');
    });

    test('mañana con minutos', () {
      expect(utils.formatearHoraAMPM(DateTime(2026, 1, 1, 7, 5)), '7:05 AM');
    });

    test('tarde con minutos', () {
      expect(utils.formatearHoraAMPM(DateTime(2026, 1, 1, 14, 30)), '2:30 PM');
    });

    test('noche', () {
      expect(utils.formatearHoraAMPM(DateTime(2026, 1, 1, 23, 59)), '11:59 PM');
    });

    test('11:59 AM', () {
      expect(utils.formatearHoraAMPM(DateTime(2026, 1, 1, 11, 59)), '11:59 AM');
    });
  });

  group('periodo', () {
    test('AM para hora antes de mediodía', () {
      expect(utils.periodo(DateTime(2026, 1, 1, 8, 0)), 'AM');
    });

    test('PM para hora después de mediodía', () {
      expect(utils.periodo(DateTime(2026, 1, 1, 15, 0)), 'PM');
    });

    test('AM para medianoche', () {
      expect(utils.periodo(DateTime(2026, 1, 1, 0, 0)), 'AM');
    });
  });

  group('partesHora12h', () {
    test('medianoche exacta', () {
      expect(utils.partesHora12h(DateTime(2026, 1, 1, 0, 0)),
          (hora: 12, minuto: 0, periodo: 'AM'));
    });

    test('mediodía exacto', () {
      expect(utils.partesHora12h(DateTime(2026, 1, 1, 12, 0)),
          (hora: 12, minuto: 0, periodo: 'PM'));
    });

    test('mañana con minutos', () {
      expect(utils.partesHora12h(DateTime(2026, 1, 1, 7, 5)),
          (hora: 7, minuto: 5, periodo: 'AM'));
    });

    test('tarde con minutos', () {
      expect(utils.partesHora12h(DateTime(2026, 1, 1, 14, 30)),
          (hora: 2, minuto: 30, periodo: 'PM'));
    });

    test('noche', () {
      expect(utils.partesHora12h(DateTime(2026, 1, 1, 23, 59)),
          (hora: 11, minuto: 59, periodo: 'PM'));
    });

    test('11:59 AM', () {
      expect(utils.partesHora12h(DateTime(2026, 1, 1, 11, 59)),
          (hora: 11, minuto: 59, periodo: 'AM'));
    });
  });

  group('iconoSegunHora', () {
    test('mañana (5-12)', () {
      expect(utils.iconoSegunHora(7), Icons.wb_sunny_outlined);
      expect(utils.iconoSegunHora(11), Icons.wb_sunny_outlined);
    });

    test('tarde (12-17)', () {
      expect(utils.iconoSegunHora(12), Icons.sunny_snowing);
      expect(utils.iconoSegunHora(15), Icons.sunny_snowing);
    });

    test('atardecer (17-21)', () {
      expect(utils.iconoSegunHora(18), Icons.nightlight_round);
      expect(utils.iconoSegunHora(20), Icons.nightlight_round);
    });

    test('noche (21-5)', () {
      expect(utils.iconoSegunHora(23), Icons.nights_stay_outlined);
      expect(utils.iconoSegunHora(3), Icons.nights_stay_outlined);
    });
  });

  group('textoTiempoRestante', () {
    test('menos de una hora', () {
      final ahora = DateTime(2026, 5, 4, 10, 0);
      final alarma = DateTime(2026, 5, 4, 10, 30);
      expect(utils.textoTiempoRestante(alarma, ahora), '30min');
    });

    test('varias horas y minutos', () {
      final ahora = DateTime(2026, 5, 4, 10, 0);
      final alarma = DateTime(2026, 5, 4, 12, 15);
      expect(utils.textoTiempoRestante(alarma, ahora), '2h 15min');
    });

    test('solo una hora exacta', () {
      final ahora = DateTime(2026, 5, 4, 10, 0);
      final alarma = DateTime(2026, 5, 4, 11, 0);
      expect(utils.textoTiempoRestante(alarma, ahora), '1h 0min');
    });

    test('null si la alarma ya pasó', () {
      final ahora = DateTime(2026, 5, 4, 10, 0);
      final alarma = DateTime(2026, 5, 4, 9, 0);
      expect(utils.textoTiempoRestante(alarma, ahora), isNull);
    });

    test('null si la alarma es exactamente ahora', () {
      final ahora = DateTime(2026, 5, 4, 10, 0);
      final alarma = DateTime(2026, 5, 4, 10, 0);
      expect(utils.textoTiempoRestante(alarma, ahora), isNull);
    });

    test('menos de 1 min cuando quedan menos de 60 segundos', () {
      final ahora = DateTime(2026, 5, 4, 10, 0, 0);
      final alarma = DateTime(2026, 5, 4, 10, 0, 45);
      expect(utils.textoTiempoRestante(alarma, ahora), 'menos de 1 min');
    });

    test('varias horas sin minutos muestra Xh 0min', () {
      final ahora = DateTime(2026, 5, 4, 10, 0);
      final alarma = DateTime(2026, 5, 4, 13, 0);
      expect(utils.textoTiempoRestante(alarma, ahora), '3h 0min');
    });
  });

  group('direccionAleatoria', () {
    test('siempre devuelve uno de los 4 vectores válidos', () {
      for (var i = 0; i < 100; i++) {
        final dir = utils.direccionAleatoria();
        final esValida = (dir == const Offset(1, 0) ||
            dir == const Offset(-1, 0) ||
            dir == const Offset(0, 1) ||
            dir == const Offset(0, -1));
        expect(esValida, isTrue, reason: 'Dirección inválida: $dir');
      }
    });
  });

  group('iconoDireccion', () {
    test('derecha', () {
      expect(utils.iconoDireccion(const Offset(1, 0)), Icons.arrow_forward);
    });

    test('izquierda', () {
      expect(utils.iconoDireccion(const Offset(-1, 0)), Icons.arrow_back);
    });

    test('abajo', () {
      expect(utils.iconoDireccion(const Offset(0, 1)), Icons.arrow_downward);
    });

    test('arriba', () {
      expect(utils.iconoDireccion(const Offset(0, -1)), Icons.arrow_upward);
    });
  });

  group('textoDireccion', () {
    test('derecha', () {
      expect(utils.textoDireccion(const Offset(1, 0)), 'desliza a la derecha');
    });

    test('izquierda', () {
      expect(utils.textoDireccion(const Offset(-1, 0)), 'desliza a la izquierda');
    });

    test('abajo', () {
      expect(utils.textoDireccion(const Offset(0, 1)), 'desliza hacia abajo');
    });

    test('arriba', () {
      expect(utils.textoDireccion(const Offset(0, -1)), 'desliza hacia arriba');
    });
  });
}
