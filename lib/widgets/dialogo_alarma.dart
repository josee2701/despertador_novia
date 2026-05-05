import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/alarma.dart';
import '../utils/constantes.dart';

/// Callback usado al guardar una alarma desde el diálogo.
typedef GuardarAlarmaCallback = void Function(
  int hora,
  int minuto,
  String etiqueta,
  List<int> dias,
);

/// Modal flotante unificado para crear y editar alarmas.
///
/// Flujo en dos pasos:
/// 1. Paso simple (siempre visible): selector de hora grande + "Listo" + "Configurar"
/// 2. Paso completo (al tocar "Configurar"): nombre + días de repetición + "Guardar"
///
/// Usa TimePicker nativo en formato AM/PM.
class DialogoAlarma extends StatefulWidget {
  /// Alarma existente (null = creando nueva).
  final Alarma? alarma;

  /// Callback al guardar. Recibe hora, minuto, etiqueta y días.
  final GuardarAlarmaCallback onGuardar;

  const DialogoAlarma({
    super.key,
    this.alarma,
    required this.onGuardar,
  });

  @override
  State<DialogoAlarma> createState() => _DialogoAlarmaState();
}

class _DialogoAlarmaState extends State<DialogoAlarma> {
  bool _modoConfiguracion = false;
  late TimeOfDay _horaSeleccionada;
  late String _etiqueta;
  late List<int> _diasSeleccionados;
  final _controladorEtiqueta = TextEditingController();

  bool get _esEdicion => widget.alarma != null;

  @override
  void initState() {
    super.initState();
    if (_esEdicion) {
      _horaSeleccionada = TimeOfDay(
        hour: widget.alarma!.hora.hour,
        minute: widget.alarma!.hora.minute,
      );
      _etiqueta = widget.alarma!.etiqueta;
      _diasSeleccionados = List<int>.from(widget.alarma!.diasSemana);
    } else {
      _horaSeleccionada = TimeOfDay.now();
      _etiqueta = '';
      _diasSeleccionados = [];
    }
    _controladorEtiqueta.text = _etiqueta;
  }

  @override
  void dispose() {
    _controladorEtiqueta.dispose();
    super.dispose();
  }

  Future<void> _seleccionarHora() async {
    final nueva = await showTimePicker(
      context: context,
      initialTime: _horaSeleccionada,
      helpText: 'Selecciona la hora',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            timePickerTheme: TimePickerThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (nueva != null) {
      setState(() => _horaSeleccionada = nueva);
      HapticFeedback.lightImpact();
    }
  }

  String _textoHora() {
    final h = _horaSeleccionada.hour;
    final m = _horaSeleccionada.minute.toString().padLeft(2, '0');
    final hora12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final periodo = h >= 12 ? 'PM' : 'AM';
    return '$hora12:$m $periodo';
  }

  void _guardarSimple() {
    widget.onGuardar(
      _horaSeleccionada.hour,
      _horaSeleccionada.minute,
      _etiqueta,
      [],
    );
    HapticFeedback.mediumImpact();
  }

  void _guardarCompleto() {
    widget.onGuardar(
      _horaSeleccionada.hour,
      _horaSeleccionada.minute,
      _controladorEtiqueta.text.trim(),
      List<int>.from(_diasSeleccionados),
    );
    HapticFeedback.mediumImpact();
  }

  void _cancelar() {
    Navigator.pop(context);
  }

  /// Selecciona el ícono según la hora del día.
  IconData _iconoHora() {
    final h = _horaSeleccionada.hour;
    if (h >= 5 && h < 12) return Icons.wb_sunny_outlined;
    if (h >= 12 && h < 17) return Icons.sunny_snowing;
    if (h >= 17 && h < 21) return Icons.nightlight_round;
    return Icons.nights_stay_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Título
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _esEdicion ? Icons.edit : Icons.alarm_add,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _esEdicion ? 'Editar alarma' : 'Nueva alarma',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Selector de hora grande
              GestureDetector(
                onTap: _seleccionarHora,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                        theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _iconoHora(),
                        size: 32,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _textoHora(),
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Toca para cambiar',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.primary.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Campos de configuración (solo en modo completo)
              if (_modoConfiguracion) ...[
                const SizedBox(height: 20),

                // Etiqueta
                Row(
                  children: [
                    Icon(Icons.label_outline, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    const Text(
                      'Nombre',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _controladorEtiqueta,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Ej: Despertar a María',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),

                const SizedBox(height: 20),

                // Días de repetición
                Row(
                  children: [
                    Icon(Icons.repeat_outlined, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    const Text(
                      'Repetir',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Acceso rápido
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ChipRapido(
                      label: 'Lun–Vie',
                      seleccionado: _diasSeleccionados.length == 5 &&
                          _diasSeleccionados.contains(1) &&
                          _diasSeleccionados.contains(5),
                      onTap: () => setState(() => _diasSeleccionados = [1, 2, 3, 4, 5]),
                    ),
                    _ChipRapido(
                      label: 'Todos',
                      seleccionado: _diasSeleccionados.length == 7,
                      onTap: () => setState(() => _diasSeleccionados = [1, 2, 3, 4, 5, 6, 7]),
                    ),
                    _ChipRapido(
                      label: 'Fin de semana',
                      seleccionado: _diasSeleccionados.length == 2 &&
                          _diasSeleccionados.contains(6) &&
                          _diasSeleccionados.contains(7),
                      onTap: () => setState(() => _diasSeleccionados = [6, 7]),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Días individuales
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: List.generate(7, (i) {
                    final dia = i + 1;
                    final activo = _diasSeleccionados.contains(dia);
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          if (activo) {
                            _diasSeleccionados.remove(dia);
                          } else {
                            _diasSeleccionados.add(dia);
                            _diasSeleccionados.sort();
                          }
                        });
                        HapticFeedback.lightImpact();
                      },
                      child: _ChipDia(
                        label: nombresDias[i],
                        activo: activo,
                      ),
                    );
                  }),
                ),

                const SizedBox(height: 6),
                Text(
                  _diasSeleccionados.isEmpty
                      ? 'Alarma de una sola vez'
                      : 'Se repite en los días seleccionados',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Botones de acción
              Row(
                children: [
                  // Cancelar
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _cancelar,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancelar'),
                    ),
                  ),

                  const SizedBox(width: 10),

                  // Listo / Configurar / Guardar
                  Expanded(
                    child: FilledButton(
                      onPressed: _modoConfiguracion ? _guardarCompleto : _guardarSimple,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(_modoConfiguracion ? 'Guardar' : 'Listo'),
                    ),
                  ),
                ],
              ),

              // Botón "Configurar" (solo en modo simple)
              if (!_modoConfiguracion) ...[
                const SizedBox(height: 10),
                Center(
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() => _modoConfiguracion = true);
                      HapticFeedback.lightImpact();
                    },
                    icon: const Icon(Icons.settings_outlined, size: 18),
                    label: const Text('Configurar repetición y nombre'),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Chip de acceso rápido para patrones de días.
class _ChipRapido extends StatelessWidget {
  final String label;
  final bool seleccionado;
  final VoidCallback onTap;

  const _ChipRapido({
    required this.label,
    required this.seleccionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: seleccionado
          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.7)
          : null,
      side: BorderSide(
        color: seleccionado
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
      ),
      onPressed: onTap,
    );
  }
}

/// Chip para día individual.
class _ChipDia extends StatelessWidget {
  final String label;
  final bool activo;

  const _ChipDia({required this.label, required this.activo});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 40,
      height: 34,
      decoration: BoxDecoration(
        color: activo
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: activo
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: activo ? FontWeight.w700 : FontWeight.w500,
            color: activo ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
