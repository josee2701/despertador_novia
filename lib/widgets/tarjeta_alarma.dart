import 'package:flutter/material.dart';

import '../models/alarma.dart';
import '../utils/constantes.dart';
import '../utils/date_utils.dart';

/// Tarjeta individual que muestra una alarma en la lista principal.
///
/// Muestra la hora, etiqueta, días de repetición y el interruptor de activación.
/// Soporta ser deslizada para eliminar (Dismissible).
class TarjetaAlarma extends StatelessWidget {
  /// La alarma a mostrar.
  final Alarma alarma;

  /// Callback cuando el usuario activa/desactiva la alarma.
  final ValueChanged<bool> onToggle;

  /// Callback cuando el usuario desliza para eliminar.
  final VoidCallback onEliminar;

  /// Callback cuando el usuario toca la tarjeta para editar.
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
    return Dismissible(
      key: ValueKey(alarma.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onEliminar(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Card(
        elevation: 2,
        surfaceTintColor: Theme.of(context).colorScheme.surfaceTint,
        color: alarma.activa ? Colors.white : Colors.grey[200],
        margin: const EdgeInsets.only(bottom: 12.0),
        shadowColor: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
          child: ListTile(
            onTap: onTap,
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.alarm,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                size: 24,
              ),
            ),
            title: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  formatearHora(alarma.hora),
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                    color: alarma.activa ? Colors.black87 : Colors.grey,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  periodo(alarma.hora),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: alarma.activa
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                  ),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.notifications_none_rounded,
                      size: 14,
                      color: alarma.activa ? Colors.grey[600] : Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      alarma.etiqueta,
                      style: TextStyle(
                        color: alarma.activa ? Colors.grey[700] : Colors.grey,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                if (alarma.pospuesta)
                  const Text(
                    'Pospuesta',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (alarma.diasSemana.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                      children: List.generate(7, (i) {
                        final activo = alarma.diasSemana.contains(i + 1);
                        return Padding(
                          padding: const EdgeInsets.only(right: 5),
                          child: Text(
                            nombresDias[i],
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight:
                                  activo ? FontWeight.w700 : FontWeight.normal,
                              color: activo
                                  ? (alarma.activa
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.grey)
                                  : Colors.grey[300],
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: alarma.activa ? Colors.grey[500] : Colors.grey,
                ),
                const SizedBox(width: 8),
                Switch(
                  value: alarma.activa,
                  onChanged: onToggle,
                  activeTrackColor: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
