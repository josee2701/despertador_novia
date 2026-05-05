import 'package:flutter/material.dart';

/// Widget que muestra la hora actual en formato HH:MM:SS.
///
/// Recibe la hora como parámetro (el presenter la actualiza cada segundo)
/// y la renderiza con un estilo grande y elegante.
class RelojWidget extends StatelessWidget {
  /// Hora actual a mostrar.
  final DateTime ahora;

  const RelojWidget({super.key, required this.ahora});

  @override
  Widget build(BuildContext context) {
    final horas = ahora.hour.toString().padLeft(2, '0');
    final minutos = ahora.minute.toString().padLeft(2, '0');
    final segundos = ahora.second.toString().padLeft(2, '0');

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.access_time,
          color: Colors.white.withValues(alpha: 0.7),
          size: 28,
        ),
        const SizedBox(width: 8),
        Text(
          '$horas:$minutos:$segundos',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 56,
            fontWeight: FontWeight.w200,
            letterSpacing: 4,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
