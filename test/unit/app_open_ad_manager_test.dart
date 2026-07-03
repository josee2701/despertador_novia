import 'package:flutter_test/flutter_test.dart';

import 'package:despertador_novia/services/app_open_ad_manager.dart';

/// Tests de la política PURA de candados del App Open Ad.
///
/// Solo se prueba [AppOpenAdManager.puedeMostrar] y los métodos de estado
/// asociados. El plumbing del SDK de AdMob (cargar/mostrar/dispose) no se
/// prueba aquí porque requiere el binding nativo, no disponible en unit tests.
void main() {
  group('AppOpenAdManager - política de candados', () {
    test('no muestra si hay alarma sonando', () {
      final m = AppOpenAdManager();
      m.marcarEnPausa();
      m.debugSetAdCargado(true);

      expect(m.puedeMostrar(hayAlarmaSonando: true), isFalse);
    });

    test('no muestra en cold start (sin pausa previa)', () {
      final m = AppOpenAdManager();
      m.debugSetAdCargado(true);

      // Nunca se llamó marcarEnPausa → arranque en frío, no debe mostrar.
      expect(m.puedeMostrar(hayAlarmaSonando: false), isFalse);
    });

    test('no muestra si no hay ad cargado', () {
      final m = AppOpenAdManager();
      m.marcarEnPausa();
      m.debugSetAdCargado(false);

      expect(m.puedeMostrar(hayAlarmaSonando: false), isFalse);
    });

    test('muestra la primera vez: resume caliente, sin alarma, ad cargado', () {
      final m = AppOpenAdManager();
      m.marcarEnPausa();
      m.debugSetAdCargado(true);

      // Sin _ultimaVez registrada todavía.
      expect(m.puedeMostrar(hayAlarmaSonando: false), isTrue);
    });

    test('respeta frequency cap: no muestra dentro de 4h', () {
      var ahora = DateTime(2030, 1, 1, 8, 0);
      final m = AppOpenAdManager(reloj: () => ahora);
      m.marcarEnPausa();
      m.debugSetAdCargado(true);

      // Se muestra una vez en t0.
      m.registrarMostrado();

      // Avanza a t0 + 3h59m → todavía dentro del cap.
      ahora = DateTime(2030, 1, 1, 11, 59);
      expect(m.puedeMostrar(hayAlarmaSonando: false), isFalse);
    });

    test('permite mostrar tras superar 4h', () {
      var ahora = DateTime(2030, 1, 1, 8, 0);
      final m = AppOpenAdManager(reloj: () => ahora);
      m.marcarEnPausa();
      m.debugSetAdCargado(true);

      m.registrarMostrado();

      // Avanza a t0 + 4h1m → supera el cap.
      ahora = DateTime(2030, 1, 1, 12, 1);
      expect(m.puedeMostrar(hayAlarmaSonando: false), isTrue);
    });
  });
}
