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
  /// Callback que se ejecuta cuando el usuario completa el deslizamiento.
  final VoidCallback onDesbloqueado;

  /// Umbral de progreso necesario para considerar el deslizamiento exitoso.
  /// Valor entre 0.0 y 1.0 (por defecto 0.75 = 75% del recorrido).
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
    with SingleTickerProviderStateMixin {
  late Offset _direccionObjetivo;
  Offset _arrastre = Offset.zero;
  bool _completado = false;
  late AnimationController _animacionReset;

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
  }

  @override
  void dispose() {
    _animacionReset.dispose();
    super.dispose();
  }

  /// Cambia la dirección objetivo a una nueva aleatoria.
  void _cambiarDireccion() {
    setState(() {
      _direccionObjetivo = direccionAleatoria();
    });
  }

  /// Maneja el movimiento del dedo durante el arrastre.
  void _onPanUpdate(DragUpdateDetails details) {
    if (_completado) return;

    setState(() {
      _arrastre += details.delta;
    });

    // Vibrar cuando se acerca al umbral
    final progreso = _calcularProgreso();
    if (progreso > 0.5 && progreso < 0.55) {
      HapticFeedback.lightImpact();
    }
  }

  /// Maneja el momento cuando el usuario levanta el dedo.
  void _onPanEnd(DragEndDetails details) {
    if (_completado) return;

    final progreso = _calcularProgreso();

    if (progreso >= widget.umbral) {
      // Éxito: ejecutar callback
      HapticFeedback.heavyImpact();
      setState(() => _completado = true);
      widget.onDesbloqueado();
    } else {
      // Fallo: verificar si deslizó en la dirección opuesta
      final direccionCorrecta = _estaEnDireccionCorrecta();
      if (!direccionCorrecta && _arrastre.distance > 20) {
        // Deslizó en dirección incorrecta, cambiar la dirección objetivo
        _cambiarDireccion();
        HapticFeedback.mediumImpact();
      }

      // Animar de vuelta al centro
      _animacionReset.forward(from: 0.0);
    }
  }

  /// Verifica si el arrastre va en la dirección del objetivo.
  bool _estaEnDireccionCorrecta() {
    if (_direccionObjetivo.dx != 0) {
      return (_arrastre.dx * _direccionObjetivo.dx) > 0;
    }
    return (_arrastre.dy * _direccionObjetivo.dy) > 0;
  }

  /// Calcula el progreso proyectando el arrastre sobre el eje de la dirección objetivo.
  double _calcularProgreso() {
    final dot = _arrastre.dx * _direccionObjetivo.dx +
        _arrastre.dy * _direccionObjetivo.dy;

    final size = context.size;
    if (size == null) return 0.0;

    final maxDistancia = _direccionObjetivo.dx != 0
        ? size.width * 0.4
        : size.height * 0.4;

    return (dot / maxDistancia).clamp(0.0, 1.0);
  }

  /// Color de la barra de progreso según qué tan cerca está del umbral.
  Color _colorProgreso(double progreso) {
    if (progreso >= widget.umbral) return Colors.green;
    if (progreso > 0.5) return Colors.orange;
    return Colors.grey.shade300;
  }

  @override
  Widget build(BuildContext context) {
    final progreso = _calcularProgreso();

    return GestureDetector(
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: Container(
        width: double.infinity,
        height: 80,
        margin: const EdgeInsets.symmetric(horizontal: 40),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Fondo de la pista con dirección indicada
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
                  Icon(
                    iconoDireccion(_direccionObjetivo),
                    color: Colors.white.withValues(alpha: 0.6),
                    size: 28,
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

            // Barra de progreso visual
            AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: (context.size?.width ?? 300) * progreso,
              height: 80,
              decoration: BoxDecoration(
                color: _colorProgreso(progreso).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(40),
              ),
            ),

            // Control deslizante (thumb)
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
                  child: Icon(
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
  }
}
