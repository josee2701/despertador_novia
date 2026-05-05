import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/date_utils.dart';

/// Widget interactivo invisible que requiere deslizar en una dirección aleatoria
/// para confirmar una acción (como apagar una alarma).
///
/// El widget es completamente invisible — solo muestra una barra de progreso
/// sutil conforme el usuario arrastra. La dirección se indica fuera del widget
/// mediante el callback `onDireccionCambiada`.
class SlideDesbloqueo extends StatefulWidget {
  final VoidCallback onDesbloqueado;
  final double umbral;
  final ValueChanged<String>? onDireccionCambiada;

  const SlideDesbloqueo({
    super.key,
    required this.onDesbloqueado,
    this.umbral = 0.75,
    this.onDireccionCambiada,
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
  double _anchoDisponible = 0.0;

  @override
  void initState() {
    super.initState();
    _direccionObjetivo = direccionAleatoria();
    _notificarDireccion();
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
  }

  @override
  void dispose() {
    _animacionReset.dispose();
    super.dispose();
  }

  void _notificarDireccion() {
    widget.onDireccionCambiada?.call(textoDireccion(_direccionObjetivo));
  }

  void _cambiarDireccion() {
    setState(() {
      _direccionObjetivo = direccionAleatoria();
    });
    _notificarDireccion();
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
    return Colors.white.withValues(alpha: 0.3);
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
          behavior: HitTestBehavior.translucent,
          child: SizedBox(
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Línea sutil de progreso (invisible hasta que se arrastra)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: _anchoDisponible * 0.8 * progreso,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _colorProgreso(progreso).withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Control deslizante (visible desde el inicio)
                AnimatedOpacity(
                  opacity: _completado ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 300),
                  child: Transform.translate(
                    offset: _arrastre,
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.power_settings_new_rounded,
                        color: Colors.white.withValues(alpha: 0.7),
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
