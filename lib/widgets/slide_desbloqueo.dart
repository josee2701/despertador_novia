import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/date_utils.dart';

/// Widget interactivo que requiere deslizar en una dirección aleatoria
/// para confirmar una acción (como apagar una alarma).
///
/// La dirección se elige aleatoriamente al crear el widget y cambia cada vez
/// que el usuario intenta deslizar en la dirección incorrecta o no alcanza
/// el umbral requerido.
///
/// Incluye retroalimentación visual:
/// - Flecha indicando la dirección correcta
/// - Barra de progreso que se llena conforme el usuario desliza
/// - Vibración háptica al alcanzar el umbral
class SlideDesbloqueo extends StatefulWidget {
  final VoidCallback onDesbloqueado;
  final double umbral;

  const SlideDesbloqueo({
    super.key,
    required this.onDesbloqueado,
    this.umbral = 0.75,
  });

  @override
  State<SlideDesbloqueo> createState() => _SlideDesbloqueoState();
}

class _SlideDesbloqueoState extends State<SlideDesbloqueo>
    with TickerProviderStateMixin {
  late Offset _direccionObjetivo;
  Offset _arrastre = Offset.zero;
  bool _completado = false;
  late AnimationController _animacionReset;
  late AnimationController _pulseController;
  double _anchoDisponible = 0.0;

  @override
  void initState() {
    super.initState();
    _direccionObjetivo = direccionAleatoria();
    _animacionReset = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(() {
        if (_animacionReset.isAnimating) {
          setState(() {
            _arrastre = _arrastre * (1.0 - _animacionReset.value);
          });
        }
      });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animacionReset.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _cambiarDireccion() {
    setState(() {
      _direccionObjetivo = direccionAleatoria();
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_completado) return;

    setState(() {
      _arrastre += details.delta;
    });

    final progreso = _calcularProgreso();
    if (progreso > 0.5 && progreso < 0.55) {
      HapticFeedback.lightImpact();
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_completado) return;

    final progreso = _calcularProgreso();

    if (progreso >= widget.umbral) {
      HapticFeedback.heavyImpact();
      setState(() => _completado = true);
      widget.onDesbloqueado();
    } else {
      final direccionCorrecta = _estaEnDireccionCorrecta();
      if (!direccionCorrecta && _arrastre.distance > 20) {
        _cambiarDireccion();
        HapticFeedback.mediumImpact();
      }

      _animacionReset.forward(from: 0.0);
    }
  }

  bool _estaEnDireccionCorrecta() {
    if (_direccionObjetivo.dx != 0) {
      return (_arrastre.dx * _direccionObjetivo.dx) > 0;
    }
    return (_arrastre.dy * _direccionObjetivo.dy) > 0;
  }

  double _calcularProgreso() {
    final dot = _arrastre.dx * _direccionObjetivo.dx +
        _arrastre.dy * _direccionObjetivo.dy;

    if (_anchoDisponible == 0) return 0.0;

    final maxDistancia = _direccionObjetivo.dx != 0
        ? _anchoDisponible * 0.4
        : 80.0 * 0.4;

    return (dot / maxDistancia).clamp(0.0, 1.0);
  }

  Color _colorProgreso(double progreso) {
    if (progreso >= widget.umbral) return Colors.green;
    if (progreso > 0.5) return Colors.orange;
    return Colors.grey.shade300;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _anchoDisponible = constraints.maxWidth;
        final progreso = _calcularProgreso();

        return GestureDetector(
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          child: SizedBox(
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Fondo de la pista
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade800,
                    borderRadius: BorderRadius.circular(40),
                    border: Border.all(
                      color: _colorProgreso(progreso).withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          final scale = 1.0 + (_pulseController.value * 0.15);
                          return Transform.scale(
                            scale: scale,
                            child: child,
                          );
                        },
                        child: Icon(
                          iconoDireccion(_direccionObjetivo),
                          color: Colors.white.withValues(alpha: 0.6),
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Desliza para apagar',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),

                // Barra de progreso
                AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: _anchoDisponible * progreso,
                  height: 80,
                  decoration: BoxDecoration(
                    color: _colorProgreso(progreso).withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(40),
                  ),
                ),

                // Control deslizante
                AnimatedOpacity(
                  opacity: _completado ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 300),
                  child: Transform.translate(
                    offset: _arrastre,
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.power_settings_new_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
