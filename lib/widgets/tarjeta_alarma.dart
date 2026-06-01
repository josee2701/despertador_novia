import 'package:flutter/material.dart';

import '../models/alarma.dart';
import '../utils/constantes.dart';
import '../utils/date_utils.dart';

/// Tarjeta individual que muestra una alarma en la lista principal.
///
/// Muestra la hora en formato AM/PM, etiqueta, días de repetición
/// y el interruptor de activación. Soporta swipe para eliminar.
class TarjetaAlarma extends StatelessWidget {
  final Alarma alarma;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEliminar;
  final VoidCallback onTap;

  const TarjetaAlarma({
    super.key,
    required this.alarma,
    required this.onToggle,
    required this.onEliminar,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final esHoy = _esParaHoy();
    final icono = iconoSegunHora(alarma.horaDelDia);
    final horaAMPM = formatearHoraAMPM(
      DateTime(2000, 1, 1, alarma.horaDelDia, alarma.minutoDelDia),
    );

    return Dismissible(
      key: ValueKey(alarma.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onEliminar(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.red[400]!, Colors.red[700]!],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.delete_forever, color: Colors.white, size: 28),
      ),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: alarma.activa ? 1.0 : 0.65,
        child: Card(
          elevation: alarma.activa ? 2 : 0,
          surfaceTintColor: Theme.of(context).colorScheme.surfaceTint,
          color: alarma.activa ? Colors.white : Colors.grey[200],
          margin: const EdgeInsets.only(bottom: 12.0),
          shadowColor: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: Row(
                children: [
                  // Icono dinámico según hora del día
                  Stack(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Theme.of(context).colorScheme.primaryContainer.withValues(alpha: alarma.activa ? 0.6 : 0.3),
                              Theme.of(context).colorScheme.primaryContainer.withValues(alpha: alarma.activa ? 0.3 : 0.15),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          icono,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          size: 24,
                        ),
                      ),
                      if (alarma.pospuesta)
                        Positioned(
                          top: 2,
                          right: 2,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(width: 14),

                  // Contenido principal
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              horaAMPM,
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: alarma.activa ? Colors.black87 : Colors.grey,
                              ),
                            ),
                            if (esHoy) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Theme.of(context).colorScheme.primary,
                                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: const Text(
                                  'HOY',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),

                        // Etiqueta
                        Text(
                          alarma.etiqueta,
                          style: TextStyle(
                            color: alarma.activa ? Colors.grey[700] : Colors.grey,
                            fontSize: 13,
                          ),
                        ),

                        // Días de repetición como chips pequeños
                        if (alarma.diasSemana.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: List.generate(7, (i) {
                                final activo = alarma.diasSemana.contains(i + 1);
                                return AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 28,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      gradient: activo
                                          ? LinearGradient(
                                              colors: alarma.activa
                                                  ? [
                                                      Theme.of(context).colorScheme.primary,
                                                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                                                    ]
                                                  : [Colors.grey[400]!, Colors.grey[500]!],
                                            )
                                          : null,
                                      color: activo ? null : Colors.grey[100],
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Center(
                                      child: Text(
                                        nombresDias[i],
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: activo ? FontWeight.w700 : FontWeight.normal,
                                          color: activo ? Colors.white : Colors.grey[400],
                                        ),
                                      ),
                                    ),
                                  );
                              }),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Switch de activación
                  Transform.scale(
                    scale: 0.85,
                    child: Switch(
                      value: alarma.activa,
                      onChanged: onToggle,
                      activeTrackColor: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Verifica si la alarma está programada para hoy.
  bool _esParaHoy() {
    final ahora = DateTime.now();
    final proximoDisparo = proximaFecha(
      alarma.horaDelDia,
      alarma.minutoDelDia,
      alarma.diasSemana,
    );
    return proximoDisparo.year == ahora.year &&
        proximoDisparo.month == ahora.month &&
        proximoDisparo.day == ahora.day;
  }
}
