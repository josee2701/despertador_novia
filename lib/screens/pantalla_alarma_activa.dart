import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/alarma.dart';
import '../utils/date_utils.dart';
import '../widgets/slide_desbloqueo.dart';

/// Pantalla de pantalla completa que se muestra cuando una alarma está sonando.
///
/// Diseño:
/// - Fondo con gradiente oscuro
/// - Etiqueta de la alarma centrada arriba
/// - Hora actual en grande en el centro
/// - Instrucción de dirección debajo de la hora
/// - Widget de deslizar invisible en la parte inferior
/// - Countdown de 5s tras desbloqueo exitoso
class PantallaAlarmaActiva extends StatefulWidget {
  final Alarma alarma;
  final VoidCallback onDetener;
  final VoidCallback onPosponer;
  final VoidCallback? onCerrarConConfirmacion; // ← NUEVO

  const PantallaAlarmaActiva({
    super.key,
    required this.alarma,
    required this.onDetener,
    required this.onPosponer,
    this.onCerrarConConfirmacion, // ← NUEVO
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

  bool _desbloqueado = false;
  int _countdownSegundos = 5;
  Timer? _countdownTimer;

  String _direccionTexto = '';

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _ahora = DateTime.now());
    });

    _timerBotones = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_contadorBotones <= 1) {
        t.cancel();
        if (mounted) setState(() => _mostrarBotones = true);
      } else {
        if (mounted) setState(() => _contadorBotones--);
      }
    });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timerBotones?.cancel();
    _countdownTimer?.cancel();
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

  void _onDireccionCambiada(String direccion) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _direccionTexto = direccion);
    });
  }

  void _iniciarCountdown() {
    if (!mounted) return;
    setState(() {
      _desbloqueado = true;
      _countdownSegundos = _kDuracionCountdown;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdownSegundos <= 1) {
        t.cancel();
        if (mounted) {
          // Solo lanzar confirmación si (a) el callback existe Y (b) no es ya la confirmación.
          // Sin la segunda condición → loop infinito.
          if (widget.onCerrarConConfirmacion != null &&
              !widget.alarma.confirmacionPendiente) {
            widget.onCerrarConConfirmacion!();
            Navigator.of(context).pop(); // ← cerrar pantalla tras lanzar confirmación
          } else {
            _detener(); // confirmación final o sin callback → detenida definitivamente
          }
        }
      } else {
        if (mounted) setState(() => _countdownSegundos--);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final partes = partesHora12h(_ahora);
    final horas = partes.hora.toString();
    final minutos = partes.minuto.toString().padLeft(2, '0');
    final periodo = partes.periodo;

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
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

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
                      const SizedBox(width: 8),
                      Text(
                        periodo,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 22,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 1),

                if (_desbloqueado)
                  _CountdownWidget(
                    segundos: _countdownSegundos,
                    esConfirmacion: widget.alarma.confirmacionPendiente,
                  )
                else
                  Column(
                    children: [
                      Text(
                        'Para apagar, $_direccionTexto',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Desliza en esa dirección sobre el botón',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),

                const SizedBox(height: 32),

                if (!_desbloqueado)
                  SlideDesbloqueo(
                    onDesbloqueado: _iniciarCountdown,
                    umbral: 0.75,
                    onDireccionCambiada: _onDireccionCambiada,
                  ),

                const SizedBox(height: 24),

                if (_mostrarBotones && !_desbloqueado)
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
                            minimumSize: const Size(0, 56),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _detener,
                          icon: const Icon(Icons.stop),
                          label: const Text('Detener'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red[400],
                            minimumSize: const Size(0, 56),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
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

const int _kDuracionCountdown = 5;

class _CountdownWidget extends StatelessWidget {
  final int segundos;
  final bool esConfirmacion; // ← NUEVO

  const _CountdownWidget({
    required this.segundos,
    this.esConfirmacion = false, // ← NUEVO
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          esConfirmacion ? '¡Confirma que estás despierto!' : '¡Alarma detenida!',
          style: TextStyle(
            color: Colors.green.withValues(alpha: 0.9),
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 1.0, end: segundos / _kDuracionCountdown.toDouble()),
                duration: const Duration(milliseconds: 300),
                builder: (context, value, _) {
                  return CircularProgressIndicator(
                    value: value,
                    strokeWidth: 4,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    valueColor: AlwaysStoppedAnimation(
                      Colors.green.withValues(alpha: 0.8),
                    ),
                  );
                },
              ),
            ),
            Text(
              '$segundos',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w300,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          esConfirmacion ? '¡Buenos días!' : 'Sonando por última vez...',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

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
