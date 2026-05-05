import 'package:flutter/material.dart';

import '../models/alarma.dart';
import '../presenters/alarmas_presenter.dart';
import '../screens/pantalla_alarma_activa.dart';
import '../widgets/editor_alarma.dart';
import '../widgets/reloj_widget.dart';
import '../widgets/tarjeta_alarma.dart';

/// Pantalla principal de la app — Vista del patrón MVP.
///
/// Esta clase solo se encarga de:
/// - Renderizar la interfaz de usuario
/// - Delegar todas las acciones al presenter
/// - Implementar la interfaz AlarmasView para recibir notificaciones
///
/// La lógica de negocio está completamente separada en el presenter.
class PantallaAlarmas extends StatefulWidget {
  const PantallaAlarmas({super.key});

  @override
  State<PantallaAlarmas> createState() => _PantallaAlarmasState();
}

class _PantallaAlarmasState extends State<PantallaAlarmas>
    with WidgetsBindingObserver
    implements AlarmasView {
  late final AlarmasPresenter _presenter;
  int? _idEditando;
  bool _modoNoMolestar = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _presenter = AlarmasPresenter(view: this);
    _presenter.iniciar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenter.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _presenter.onAppResumed();
    }
  }

  // ─── Implementación de AlarmasView ──────────────────────────────

  @override
  void onAlarmasCargadas() {
    if (mounted) setState(() {});
  }

  @override
  void onAlarmaAgregada() {
    if (mounted) setState(() => _idEditando = null);
  }

  @override
  void onAlarmaActualizada() {
    if (mounted) setState(() {});
  }

  @override
  void onAlarmaEliminada() {
    if (mounted) setState(() => _idEditando = null);
  }

  @override
  void onPermisoNecesario(bool necesita) {
    if (mounted && necesita) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _mostrarDialogoPermisoAlarma(),
      );
    }
  }

  @override
  void onModoNoMolestarCambiado(bool activo) {
    if (mounted) setState(() => _modoNoMolestar = activo);
  }

  @override
  void onMostrarPantallaAlarma(Alarma alarma) {
    if (!mounted) return;

    Navigator.push(
      context,
      PageRouteBuilder(
        fullscreenDialog: true,
        barrierColor: Colors.transparent,
        pageBuilder: (ctx, animation, secondaryAnimation) => PantallaAlarmaActiva(
          alarma: alarma,
          onDetener: () => _presenter.detenerAlarma(alarma),
          onPosponer: () => _presenter.posponerAlarma(alarma),
        ),
      ),
    );
  }

  @override
  BuildContext getContext() => context;

  // ─── Acciones del usuario ───────────────────────────────────────

  /// Muestra el diálogo para crear una nueva alarma.
  Future<void> _agregarAlarma() async {
    final horaElegida = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (horaElegida == null || !mounted) return;

    final controlador = TextEditingController();
    final etiqueta = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nombre de la alarma'),
        content: TextField(
          controller: controlador,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Ej: Despertar a María',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controlador.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controlador.dispose());
    if (etiqueta == null || !mounted) return;

    await _presenter.agregarAlarma(
      hora: horaElegida.hour,
      minuto: horaElegida.minute,
      etiqueta: etiqueta.trim().isEmpty ? 'Alarma' : etiqueta.trim(),
      diasSemana: [],
    );
  }

  /// Alterna el modo de edición de una alarma.
  void _toggleEdicion(int id) {
    setState(() {
      _idEditando = _idEditando == id ? null : id;
    });
  }

  /// Cancela la edición de una alarma.
  void _cancelarEdicion() {
    setState(() => _idEditando = null);
  }

  /// Guarda los cambios de una alarma editada.
  void _guardarEdicion(Alarma alarma) {
    _presenter.actualizarAlarmaCompleta(
      alarma: alarma,
      nuevaHora: alarma.hora.hour,
      nuevoMinuto: alarma.hora.minute,
      nuevaEtiqueta: alarma.etiqueta,
      nuevosDias: alarma.diasSemana,
    );
    setState(() => _idEditando = null);
  }

  /// Muestra el diálogo para solicitar permisos de alarma exacta.
  Future<void> _mostrarDialogoPermisoAlarma() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Permiso necesario'),
        content: const Text(
          'Para que las alarmas suenen a la hora exacta, esta app necesita el '
          'permiso "Alarmas y recordatorios".\n\n'
          'En la siguiente pantalla, activa el permiso y regresa a la app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _presenter.solicitarPermisoAlarmasExactas();
            },
            child: const Text('Ir a Configuración'),
          ),
        ],
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final alarmas = _presenter.alarmas;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Mis Alarmas'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // ── Header con reloj y próxima alarma ──
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0D47A1),
                  Color(0xFF1976D2),
                  Color(0xFF42A5F5),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                RelojWidget(ahora: _presenter.ahora),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.alarm,
                      color: Colors.white.withValues(alpha: 0.6),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _presenter.obtenerTextoProximaAlarma(),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Advertencia No Molestar ──
          if (_modoNoMolestar)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .errorContainer
                    .withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).colorScheme.errorContainer,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Modo No Molestar activo — Tu alarma podría no sonar',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => _presenter.abrirConfiguracion(),
                    child: const Text('Abrir config.'),
                  ),
                ],
              ),
            ),

          // ── Lista de alarmas ──
          Expanded(
            child: alarmas.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.alarm_add_outlined,
                          size: 100,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No tienes alarmas',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Toca + para crear tu primera alarma',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16.0),
                    itemCount: alarmas.length,
                    itemBuilder: (context, index) {
                      final alarma = alarmas[index];
                      final estaEditando = _idEditando == alarma.id;

                      return Column(
                        children: [
                          TarjetaAlarma(
                            alarma: alarma,
                            onToggle: (v) => _presenter.toggleAlarma(alarma, v),
                            onEliminar: () => _presenter.eliminarAlarma(alarma),
                            onTap: () => _toggleEdicion(alarma.id),
                          ),
                          if (estaEditando)
                            AnimatedSlide(
                              offset: Offset.zero,
                              duration: const Duration(milliseconds: 300),
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  left: 16,
                                  right: 16,
                                  bottom: 12,
                                ),
                                child: EditorAlarma(
                                  alarma: alarma,
                                  onGuardar: () => _guardarEdicion(alarma),
                                  onCancelar: _cancelarEdicion,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _agregarAlarma,
        child: const Icon(Icons.add),
      ),
    );
  }
}
