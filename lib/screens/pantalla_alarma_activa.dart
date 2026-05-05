import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/alarma.dart';
import '../widgets/slide_desbloqueo.dart';

/// Pantalla de pantalla completa que se muestra cuando una alarma está sonando.
///
/// Diseño:
/// - Fondo gris oscuro
/// - Etiqueta de la alarma centrada arriba
/// - Hora actual en grande en el centro
/// - Widget de deslizar aleatorio en la parte inferior
///
/// La alarma solo se puede apagar completando el gesto de deslizar en la
/// dirección correcta (aleatoria).
class PantallaAlarmaActiva extends StatefulWidget {
  /// La alarma que está sonando.
  final Alarma alarma;

  /// Callback para detener la alarma.
  final VoidCallback onDetener;

  /// Callback para posponer la alarma 5 minutos.
  final VoidCallback onPosponer;

  const PantallaAlarmaActiva({
    super.key,
    required this.alarma,
    required this.onDetener,
    required this.onPosponer,
  });

  @override
  State<PantallaAlarmaActiva> createState() => _PantallaAlarmaActivaState();
}

class _PantallaAlarmaActivaState extends State<PantallaAlarmaActiva> {
  DateTime _ahora = DateTime.now();
  Timer? _timer;
  bool _mostrarBotones = false;
  int _contadorBotones = 10;
  Timer? _timerBotones;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    // Actualizar la hora cada segundo
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _ahora = DateTime.now());
    });

    // Mostrar botones de emergencia después de 10 segundos
    _timerBotones = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_contadorBotones <= 1) {
        t.cancel();
        setState(() => _mostrarBotones = true);
      } else {
        setState(() => _contadorBotones--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timerBotones?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([]);
    super.dispose();
  }

  /// Detiene la alarma y cierra esta pantalla.
  void _detener() {
    widget.onDetener();
    if (mounted) Navigator.of(context).pop();
  }

  /// Posponer la alarma 5 minutos.
  void _posponer() {
    widget.onPosponer();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final horas = _ahora.hour.toString().padLeft(2, '0');
    final minutos = _ahora.minute.toString().padLeft(2, '0');
    final segundos = _ahora.second.toString().padLeft(2, '0');

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.grey[900],
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 1),

              // Etiqueta de la alarma
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  widget.alarma.etiqueta,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Indicador de días si es recurrente
              if (widget.alarma.diasSemana.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    widget.alarma.diasSemana.length == 7
                        ? 'Todos los días'
                        : widget.alarma.diasSemana.length == 5 &&
                                !widget.alarma.diasSemana.contains(6) &&
                                !widget.alarma.diasSemana.contains(7)
                            ? 'Lunes a viernes'
                            : 'Días seleccionados',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 14,
                    ),
                  ),
                ),

              const Spacer(flex: 1),

              // Hora actual en grande
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$horas:$minutos',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 96,
                      fontWeight: FontWeight.w100,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    segundos,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 32,
                      fontWeight: FontWeight.w200,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),

              const Spacer(flex: 1),

              // Indicador "Desliza para apagar"
              Text(
                'Apaga la alarma deslizándola',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 16),

              // Widget de deslizado aleatorio
              SlideDesbloqueo(
                onDesbloqueado: _detener,
                umbral: 0.75,
              ),

              const SizedBox(height: 24),

              // Botones de emergencia (aparecen después de 10 segundos)
              if (_mostrarBotones)
                FadeIn(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _posponer,
                        icon: const Icon(Icons.snooze),
                        label: const Text('Posponer 5 min'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white30),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _detener,
                        icon: const Icon(Icons.stop),
                        label: const Text('Detener'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red[300],
                          side: BorderSide(color: Colors.red[300]!),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}

/// Widget de animación de fade-in simple.
class FadeIn extends StatefulWidget {
  final Widget child;
  const FadeIn({super.key, required this.child});

  @override
  State<FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<FadeIn> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _animation, child: widget.child);
  }
}
