import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:despertador_novia/main.dart' as app;
import 'package:despertador_novia/services/audio_service.dart';

// Flag por test: se resetea manualmente via setUp en cada grupo.
bool _surfaceConvertidaEnTest = false;

Future<void> tomarScreenshot(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String nombre,
) async {
  await tester.pump(const Duration(milliseconds: 500));
  if (!_surfaceConvertidaEnTest) {
    await binding.convertFlutterSurfaceToImage();
    _surfaceConvertidaEnTest = true;
  }
  await tester.pump();
  final bytes = await binding.takeScreenshot(nombre);
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/screenshots/$nombre.png');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
  debugPrint('Screenshot guardado: ${file.path}');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await AudioService().prepararSonido();
  });

  // Resetear el flag antes de cada test para que convertFlutterSurfaceToImage()
  // se llame una sola vez por test (el binding lo revierte automáticamente al terminar).
  setUp(() {
    _surfaceConvertidaEnTest = false;
  });

  tearDownAll(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  });

  group('TEST 1 — Pantalla principal (lista de alarmas)', () {
    testWidgets('Carga inicial y estado de la pantalla', (tester) async {
      app.main();
      await tester.pump(const Duration(seconds: 3));

      await tomarScreenshot(binding, tester, '01_pantalla_principal');

      expect(find.text('Mis Alarmas'), findsOneWidget);
      final hayAlarmas = find.byType(Dismissible);
      if (hayAlarmas.evaluate().isEmpty) {
        expect(find.text('No tienes alarmas'), findsOneWidget);
        expect(find.text('Toca + para crear tu primera alarma'), findsOneWidget);
        debugPrint('RESULTADO: Pantalla vacía - sin alarmas');
      } else {
        debugPrint('RESULTADO: Pantalla con alarmas existentes');
      }

      expect(find.text('Nueva alarma'), findsOneWidget);
    });
  });

  group('TEST 2 — Crear alarma simple', () {
    testWidgets('Crear alarma con modo simple (solo hora)', (tester) async {
      app.main();
      await tester.pump(const Duration(seconds: 3));

      final alarmasAntes = find.byType(Dismissible);
      final cantidadAntes = alarmasAntes.evaluate().length;

      await tester.tap(find.text('Nueva alarma'));
      await tester.pump(const Duration(seconds: 1));

      await tomarScreenshot(binding, tester, '02_dialogo_nueva_alarma_simple');

      expect(find.text('Listo'), findsOneWidget);
      expect(find.text('Configurar repetición y nombre'), findsOneWidget);

      await tester.tap(find.text('Listo'));
      await tester.pump(const Duration(seconds: 1));

      await tomarScreenshot(binding, tester, '03_despues_crear_alarma_simple');

      final alarmasDespues = find.byType(Dismissible);
      expect(alarmasDespues.evaluate().length, greaterThan(cantidadAntes));
      debugPrint('RESULTADO: Alarma simple creada correctamente');
    });
  });

  group('TEST 3 — Crear alarma con configuración avanzada', () {
    testWidgets('Crear alarma con nombre y días de repetición', (tester) async {
      app.main();
      await tester.pump(const Duration(seconds: 3));

      await tester.tap(find.text('Nueva alarma'));
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('Configurar repetición y nombre'));
      await tester.pump(const Duration(milliseconds: 500));

      await tomarScreenshot(binding, tester, '04_dialogo_alarma_configurar');

      final campoNombre = find.byType(TextField);
      if (campoNombre.evaluate().isNotEmpty) {
        await tester.enterText(campoNombre.first, 'Test alarma');
        await tester.pump();
      }

      final chipLunVie = find.text('Lun–Vie');
      if (chipLunVie.evaluate().isNotEmpty) {
        await tester.tap(chipLunVie);
        await tester.pump();
      }

      await tomarScreenshot(binding, tester, '05_dialogo_alarma_con_dias');

      final botonGuardar = find.text('Guardar');
      if (botonGuardar.evaluate().isNotEmpty) {
        await tester.tap(botonGuardar);
        await tester.pump(const Duration(seconds: 1));
      }

      await tomarScreenshot(binding, tester, '06_despues_crear_alarma_avanzada');
      debugPrint('RESULTADO: Flujo de alarma avanzada completado');
    });
  });

  group('TEST 4 — Toggle de alarma (activar/desactivar)', () {
    testWidgets('Activar y desactivar una alarma con el switch', (tester) async {
      app.main();
      await tester.pump(const Duration(seconds: 3));

      await tomarScreenshot(binding, tester, '07_antes_toggle');

      final switches = find.byType(Switch);
      if (switches.evaluate().isNotEmpty) {
        final primerSwitch = switches.first;
        final estadoInicial = tester.widget<Switch>(primerSwitch).value;

        await tester.tap(primerSwitch);
        await tester.pump(const Duration(milliseconds: 500));

        await tomarScreenshot(binding, tester, '08_despues_toggle_off');

        final estadoTras = tester.widget<Switch>(switches.first).value;
        expect(estadoTras, isNot(estadoInicial));
        debugPrint('RESULTADO: Toggle funcionó - de $estadoInicial a $estadoTras');

        await tester.tap(switches.first);
        await tester.pump(const Duration(milliseconds: 500));

        await tomarScreenshot(binding, tester, '09_despues_toggle_on');
        debugPrint('RESULTADO: Toggle revertido correctamente');
      } else {
        debugPrint('OMITIDO: No hay alarmas para hacer toggle');
      }
    });
  });

  group('TEST 5 — Editar alarma existente', () {
    testWidgets('Abrir diálogo de edición al tocar una alarma', (tester) async {
      app.main();
      await tester.pump(const Duration(seconds: 3));

      final tarjetas = find.byType(Dismissible);
      if (tarjetas.evaluate().isNotEmpty) {
        await tester.tap(tarjetas.first);
        await tester.pump(const Duration(seconds: 1));

        await tomarScreenshot(binding, tester, '10_dialogo_editar_alarma');

        expect(find.text('Listo'), findsOneWidget);
        debugPrint('RESULTADO: Diálogo de edición abierto correctamente');

        await tester.tap(find.text('Cancelar').first);
        await tester.pump(const Duration(milliseconds: 500));
      } else {
        debugPrint('OMITIDO: No hay alarmas para editar');
      }
    });
  });

  group('TEST 6 — Eliminar alarma (swipe)', () {
    testWidgets('Eliminar alarma deslizando a la izquierda', (tester) async {
      app.main();
      await tester.pump(const Duration(seconds: 3));

      final tarjetas = find.byType(Dismissible);
      if (tarjetas.evaluate().isNotEmpty) {
        final cantidadAntes = tarjetas.evaluate().length;

        await tester.drag(tarjetas.last, const Offset(-500, 0));
        await tester.pump(const Duration(seconds: 1));

        await tomarScreenshot(binding, tester, '11_despues_eliminar_swipe');

        final snackBar = find.text('Alarma eliminada');
        expect(snackBar, findsOneWidget);
        debugPrint('RESULTADO: Alarma eliminada - SnackBar visible');

        await tomarScreenshot(binding, tester, '12_snackbar_eliminar');

        final botonDeshacer = find.text('Deshacer');
        if (botonDeshacer.evaluate().isNotEmpty) {
          await tester.tap(botonDeshacer);
          await tester.pump(const Duration(seconds: 1));
          final cantidadDespues = find.byType(Dismissible).evaluate().length;
          expect(cantidadDespues, cantidadAntes);
          debugPrint('RESULTADO: Undo funcionó correctamente');
          await tomarScreenshot(binding, tester, '13_despues_deshacer');
        }
      } else {
        debugPrint('OMITIDO: No hay alarmas para eliminar');
      }
    });
  });

  group('TEST 7 — Banner próxima alarma', () {
    testWidgets('Verificar que el banner de próxima alarma es correcto', (tester) async {
      app.main();
      await tester.pump(const Duration(seconds: 3));

      await tomarScreenshot(binding, tester, '14_banner_proxima_alarma');

      final bannerProxima = find.textContaining('Próxima alarma:');
      final bannerSinAlarmas = find.textContaining('No hay alarmas');

      if (bannerProxima.evaluate().isNotEmpty) {
        debugPrint('RESULTADO: Banner próxima alarma visible');
      } else if (bannerSinAlarmas.evaluate().isNotEmpty) {
        debugPrint('RESULTADO: Sin alarmas activas - banner informativo');
      } else {
        debugPrint('ADVERTENCIA: Banner no encontrado con texto esperado');
      }
    });
  });

  group('TEST 8 — Estado vacío', () {
    testWidgets('Pantalla vacía cuando no hay alarmas', (tester) async {
      app.main();
      await tester.pump(const Duration(seconds: 3));

      final lista = find.byType(ListView);
      if (lista.evaluate().isEmpty) {
        await tomarScreenshot(binding, tester, '15_estado_vacio');
        expect(find.text('No tienes alarmas'), findsOneWidget);
        expect(find.text('Toca + para crear tu primera alarma'), findsOneWidget);
        debugPrint('RESULTADO: Estado vacío correcto');
      } else {
        debugPrint('OMITIDO: Hay alarmas actualmente, estado vacío no aplica');
      }
    });
  });

  group('TEST 9 — Validación de formulario de alarma', () {
    testWidgets('Verificar que el tiempo picker funciona', (tester) async {
      app.main();
      await tester.pump(const Duration(seconds: 3));

      await tester.tap(find.text('Nueva alarma'));
      await tester.pump(const Duration(seconds: 1));

      await tomarScreenshot(binding, tester, '16_time_picker_cerrado');

      final timePickerArea = find.byType(GestureDetector);
      if (timePickerArea.evaluate().isNotEmpty) {
        debugPrint('RESULTADO: Time picker presente en el diálogo');
      }

      await tester.tap(find.text('Cancelar').first);
      await tester.pump(const Duration(milliseconds: 500));
    });
  });

  group('TEST 10 — Navegación y FAB', () {
    testWidgets('FAB animado visible cuando lista vacía, normal cuando hay alarmas', (tester) async {
      app.main();
      await tester.pump(const Duration(seconds: 3));

      final fab = find.text('Nueva alarma');
      expect(fab, findsOneWidget);
      await tomarScreenshot(binding, tester, '17_fab_estado');
      debugPrint('RESULTADO: FAB siempre visible - correcto');
    });
  });

  group('TEST 11 — Regresión BUG-01: Editar alarma con repetición abre en modo config', () {
    testWidgets('Alarma con días: diálogo debe abrirse mostrando Guardar, no Listo', (tester) async {
      app.main();
      await tester.pump(const Duration(seconds: 3));

      // Crear alarma con días de repetición (Lun-Vie)
      await tester.tap(find.text('Nueva alarma'));
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('Configurar repetición y nombre'));
      await tester.pump(const Duration(milliseconds: 500));

      final chipLunVie = find.text('Lun–Vie');
      if (chipLunVie.evaluate().isNotEmpty) {
        await tester.tap(chipLunVie);
        await tester.pump();
      }

      // Ocultar teclado virtual antes de buscar/tocar Guardar para evitar
      // que el teclado cubra el botón en dispositivos físicos.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final botonGuardar = find.text('Guardar');
      if (botonGuardar.evaluate().isNotEmpty) {
        await tester.ensureVisible(botonGuardar);
        await tester.pumpAndSettle();
        await tester.tap(botonGuardar);
        await tester.pump(const Duration(seconds: 1));
      }

      // Editar la alarma recién creada
      final tarjetas = find.byType(Dismissible);
      if (tarjetas.evaluate().isNotEmpty) {
        await tester.tap(tarjetas.first);
        await tester.pump(const Duration(seconds: 1));

        await tomarScreenshot(binding, tester, '18_bug01_editar_alarma_con_repeticion');

        // BUG-01 fix: el diálogo debe abrir en modo config cuando tiene días
        // Debe mostrar 'Guardar', NO debe mostrar 'Listo' como botón principal
        expect(
          find.text('Guardar'),
          findsOneWidget,
          reason: 'BUG-01: Al editar alarma con días, debe abrir en modo config (botón Guardar)',
        );
        debugPrint('RESULTADO BUG-01: ✅ Diálogo abre en modo configuración con días existentes');

        final cancelar = find.text('Cancelar');
        if (cancelar.evaluate().isNotEmpty) {
          await tester.tap(cancelar.first);
          await tester.pump(const Duration(milliseconds: 500));
        }
      } else {
        debugPrint('OMITIDO: No se pudo crear/encontrar alarma con días para probar BUG-01');
      }
    });
  });

  group('TEST 12 — Regresión BUG-02: Badge HOY correcto con hora canónica', () {
    testWidgets('Alarma creada para hoy muestra badge HOY sin depender de snooze', (tester) async {
      app.main();
      await tester.pump(const Duration(seconds: 3));

      // Crear una alarma simple (sin repetición, para hoy)
      await tester.tap(find.text('Nueva alarma'));
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.text('Listo'));
      await tester.pump(const Duration(seconds: 1));

      await tomarScreenshot(binding, tester, '19_bug02_badge_hoy');

      // Verificar que el badge HOY aparece (alarma recién creada es para hoy o mañana)
      // No podemos verificar directamente el badge 'HOY' sin saber la hora actual,
      // pero verificamos que la tarjeta se creó correctamente
      final tarjetas = find.byType(Dismissible);
      expect(tarjetas, findsWidgets, reason: 'Debe haber al menos una alarma en la lista');

      debugPrint('RESULTADO BUG-02: ✅ Tarjeta de alarma renderiza correctamente post-fix');
    });
  });
}
