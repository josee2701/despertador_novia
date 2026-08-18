import 'dart:math' as math;

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

  /// Alto de la zona de arrastre.
  ///
  /// NO decide cuánto hay que deslizar —eso es [_recorridoVertical], una
  /// constante—, solo hasta dónde acompaña el control al dedo antes de
  /// quedarse en el borde. La pantalla la reduce si tiene poco espacio.
  final double altura;

  const SlideDesbloqueo({
    super.key,
    required this.onDesbloqueado,
    this.umbral = 0.75,
    this.onDireccionCambiada,
    this.altura = 220,
  });

  @override
  State<SlideDesbloqueo> createState() => _SlideDesbloqueoState();
}

class _SlideDesbloqueoState extends State<SlideDesbloqueo>
    with TickerProviderStateMixin {
  /// Fracción del ancho disponible que hay que recorrer para llegar al 100 %.
  static const double _fraccionAncho = 0.4;

  /// Recorrido vertical equivalente, en píxeles.
  ///
  /// Antes se calculaba sobre una constante de 80 px, así que con el umbral
  /// habitual (0.75) la alarma se apagaba con 24 px de arrastre, frente a los
  /// 82-109 px del horizontal: un roce de alguien medio dormido bastaba en la
  /// única pantalla que no debe poder descartarse por accidente. Este valor
  /// deja los dos ejes en el mismo orden de magnitud (~98 px con umbral 0.75).
  ///
  /// Es una constante y no una fracción del alto disponible a propósito: el
  /// gesto sigue al dedo aunque salga de la caja, así que el tamaño del widget
  /// no representa el recorrido posible.
  static const double _recorridoVertical = 130.0;

  /// Radio del control redondo, para no dejarlo salir de la zona visible.
  static const double _radioControl = 32.0;
  late Offset _direccionObjetivo;
  Offset _arrastre = Offset.zero;
  Offset _arrastreInicial = Offset.zero;
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
            _arrastre = _arrastreInicial * (1.0 - _animacionReset.value);
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

    // Si el usuario vuelve a arrastrar mientras el reset anima, se detiene la
    // animación: en caso contrario su listener pisaría _arrastre en cada frame
    // y el deslizamiento se sentiría congelado.
    if (_animacionReset.isAnimating) {
      _animacionReset.stop();
      _arrastreInicial = Offset.zero;
    }

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
      if (!direccionCorrecta && _arrastre.distance > 40) {
        _cambiarDireccion();
        HapticFeedback.heavyImpact();
      }

      _arrastreInicial = _arrastre;
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
        ? _anchoDisponible * _fraccionAncho
        : _recorridoVertical;

    return (dot / maxDistancia).clamp(0.0, 1.0);
  }

  /// Desplazamiento del control en pantalla: sigue al dedo, pero acotado a la
  /// zona visible. El progreso se calcula con el arrastre REAL, no con esto.
  ///
  /// Sin el tope, el `Stack` recorta el control a media pista (recorta también
  /// en horizontal, donde el arrastre siempre pudo pasarse del borde) y la
  /// persona ve desaparecer aquello que está moviendo. El avance de verdad lo
  /// cuenta la barra de progreso.
  Offset get _desplazamientoVisual {
    final margenX = math.max(0.0, _anchoDisponible / 2 - _radioControl);
    final margenY = math.max(0.0, widget.altura / 2 - _radioControl);
    return Offset(
      _arrastre.dx.clamp(-margenX, margenX),
      _arrastre.dy.clamp(-margenY, margenY),
    );
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
            height: widget.altura,
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
                    offset: _desplazamientoVisual,
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
