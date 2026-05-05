import 'package:flutter/material.dart';

import '../models/alarma.dart';
import '../utils/constantes.dart';

/// Widget de edición inline que se expande dentro de la tarjeta de alarma.
///
/// Permite editar en una sola vista:
/// - La hora de la alarma (TimePicker integrado)
/// - Los días de repetición (acceso rápido + selección individual)
/// - La etiqueta/nombre de la alarma
///
/// Tiene dos modos:
/// 1. Modo simple: solo muestra la hora actual y un botón "Configurar"
/// 2. Modo completo: después de pulsar "Configurar", muestra todos los campos
///    editables con botones "Listo" y "Cancelar"
class EditorAlarma extends StatefulWidget {
  /// La alarma que se está editando.
  final Alarma alarma;

  /// Callback cuando el usuario confirma los cambios.
  final VoidCallback onGuardar;

  /// Callback cuando el usuario cancela la edición.
  final VoidCallback onCancelar;

  const EditorAlarma({
    super.key,
    required this.alarma,
    required this.onGuardar,
    required this.onCancelar,
  });

  @override
  State<EditorAlarma> createState() => _EditorAlarmaState();
}

class _EditorAlarmaState extends State<EditorAlarma> {
  bool _modoConfiguracion = false;
  late TimeOfDay _horaSeleccionada;
  late String _etiqueta;
  late List<int> _diasSeleccionados;
  final _controladorEtiqueta = TextEditingController();

  @override
  void initState() {
    super.initState();
    _horaSeleccionada = TimeOfDay(
      hour: widget.alarma.hora.hour,
      minute: widget.alarma.hora.minute,
    );
    _etiqueta = widget.alarma.etiqueta;
    _diasSeleccionados = List<int>.from(widget.alarma.diasSemana);
    _controladorEtiqueta.text = _etiqueta;
  }

  @override
  void dispose() {
    _controladorEtiqueta.dispose();
    super.dispose();
  }

  /// Abre el selector de hora nativo.
  Future<void> _seleccionarHora() async {
    final nueva = await showTimePicker(
      context: context,
      initialTime: _horaSeleccionada,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (nueva != null) {
      setState(() => _horaSeleccionada = nueva);
    }
  }

  /// Activa el modo de configuración completa.
  void _activarConfiguracion() {
    setState(() => _modoConfiguracion = true);
  }

  /// Guarda todos los cambios y notifica al padre.
  void _guardar() {
    widget.alarma.hora = DateTime(
      widget.alarma.hora.year,
      widget.alarma.hora.month,
      widget.alarma.hora.day,
      _horaSeleccionada.hour,
      _horaSeleccionada.minute,
    );
    widget.alarma.etiqueta =
        _controladorEtiqueta.text.trim().isEmpty
            ? 'Alarma'
            : _controladorEtiqueta.text.trim();
    widget.alarma.diasSemana = List<int>.from(_diasSeleccionados);

    widget.onGuardar();
  }

  /// Cancela la edición y vuelve al estado simple.
  void _cancelar() {
    setState(() {
      _modoConfiguracion = false;
      _horaSeleccionada = TimeOfDay(
        hour: widget.alarma.hora.hour,
        minute: widget.alarma.hora.minute,
      );
      _etiqueta = widget.alarma.etiqueta;
      _diasSeleccionados = List<int>.from(widget.alarma.diasSemana);
      _controladorEtiqueta.text = _etiqueta;
    });
    widget.onCancelar();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Fila de hora + botón Configurar (siempre visible)
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: _seleccionarHora,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_horaSeleccionada.hour.toString().padLeft(2, '0')}:${_horaSeleccionada.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (!_modoConfiguracion)
              FilledButton.tonal(
                onPressed: _activarConfiguracion,
                child: const Text('Configurar'),
              ),
          ],
        ),

        // Campos de configuración completa (solo en modo configuración)
        if (_modoConfiguracion) ...[
          const SizedBox(height: 16),

          // Etiqueta
          TextField(
            controller: _controladorEtiqueta,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Nombre de la alarma',
              hintText: 'Ej: Despertar a María',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.edit),
            ),
          ),

          const SizedBox(height: 16),

          // Días de repetición
          const Text(
            'Repetir',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),

          // Acceso rápido
          Wrap(
            spacing: 6,
            children: [
              ActionChip(
                label: const Text('Lun–Vie'),
                onPressed: () => setState(() => _diasSeleccionados = [1, 2, 3, 4, 5]),
              ),
              ActionChip(
                label: const Text('Todos'),
                onPressed: () => setState(() => _diasSeleccionados = [1, 2, 3, 4, 5, 6, 7]),
              ),
              ActionChip(
                label: const Text('Fin de semana'),
                onPressed: () => setState(() => _diasSeleccionados = [6, 7]),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Días individuales
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: List.generate(7, (i) {
              final dia = i + 1;
              return FilterChip(
                label: Text(nombresDias[i]),
                selected: _diasSeleccionados.contains(dia),
                onSelected: (seleccionado) {
                  setState(() {
                    if (seleccionado) {
                      _diasSeleccionados.add(dia);
                      _diasSeleccionados.sort();
                    } else {
                      _diasSeleccionados.remove(dia);
                    }
                  });
                },
              );
            }),
          ),

          const SizedBox(height: 8),
          const Text(
            'Sin días = alarma de una sola vez',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),

          const SizedBox(height: 16),

          // Botones de acción
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _cancelar,
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _guardar,
                child: const Text('Listo'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
