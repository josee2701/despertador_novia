import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/alarma.dart';
import '../widgets/slide_desbloqueo.dart';

/// Pantalla de pantalla completa que se muestra cuando una alarma está sonando.
///
/// Diseño:
/// - Fondo con gradiente oscuro
/// - Etiqueta de la alarma centrada arriba
/// - Hora actual en grande en el centro
/// - Widget de deslizar aleatorio en la parte inferior
///
/// La alarma solo se puede apagar completando el gesto de deslizar en la
/// dirección correcta (aleatoria).
class PantallaAlarmaActiva extends StatefulWidget {
  final Alarma alarma;
  final VoidCallback onDetener;
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

class _PantallaAlarmaActivaState extends State<PantallaAlarmaActiva>
    with SingleTickerProviderStateMixin {
  DateTime _ahora = DateTime.now();
  Timer? _timer;
  bool _mostrarBotones = false;
  int _contadorBotones = 10;
  Timer? _timerBotones;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

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

    // Animación de pulso para el ícono
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timerBotones?.cancel();
    _pulseController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([]);
    super.dispose();
  }

  void _detener() {
    widget.onDetener();
    if (mounted) Navigator.of(context).pop();
  }

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
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF1a1a2e),
                Color(0xFF16213e),
                Color(0xFF0f3460),
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 1),

                // Etiqueta de la alarma
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.alarm,
                        color: Colors.white.withValues(alpha: 0.6),
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          widget.alarma.etiqueta,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w300,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Indicador de recurrencia
                if (widget.alarma.diasSemana.isNotEmpty)
                  Text(
                    widget.alarma.diasSemana.length == 7
                        ? 'Todos los días'
                        : widget.alarma.diasSemana.length == 5 &&
                                !widget.alarma.diasSemana.contains(6) &&
                                !widget.alarma.diasSemana.contains(7)
                            ? 'Lunes a viernes'
                            : '${widget.alarma.diasSemana.length} días seleccionados',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 13,
                    ),
                  ),

                const Spacer(flex: 1),

                // Hora actual en grande con animación de pulso
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    final scale = 1.0 + (_pulseController.value * 0.03);
                    return Transform.scale(
                      scale: scale,
                      child: child,
                    );
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$horas:$minutos',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 88,
                          fontWeight: FontWeight.w100,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        segundos,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 28,
                          fontWeight: FontWeight.w200,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 1),

                // Indicador de acción
                Text(
                  'Apaga la alarma deslizándola',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 14,
                  ),
                ),

                const SizedBox(height: 20),

                // Widget de deslizado aleatorio
                SlideDesbloqueo(
                  onDesbloqueado: _detener,
                  umbral: 0.75,
                ),

                const SizedBox(height: 24),

                // Botones de emergencia
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
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
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
                              horizontal: 20,
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
