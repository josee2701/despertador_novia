import 'package:flutter/material.dart';

import 'screens/pantalla_alarmas.dart';
import 'services/audio_service.dart';

/// Punto de entrada de la aplicación.
///
/// Inicializa los servicios necesarios antes de lanzar la app:
/// - Genera el archivo de audio de la alarma
/// - Configura Flutter bindings
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Preparar el sonido de alarma antes de iniciar la UI
  await AudioService().prepararSonido();

  runApp(const MiDespertadorApp());
}

/// Widget raíz de la aplicación.
///
/// Configura el tema Material 3 con el esquema de colores
/// y establece la pantalla principal.
class MiDespertadorApp extends StatelessWidget {
  const MiDespertadorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mi Despertador',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
        ),
      ),
      home: const PantallaAlarmas(),
    );
  }
}
