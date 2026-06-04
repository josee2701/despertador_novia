import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
      onScreenshot: (screenshotName, screenshotBytes, [args]) async {
        // Guardar screenshots capturados durante los tests
        return true;
      },
    );
