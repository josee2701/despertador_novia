import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/alarma.dart';
import '../presenters/alarmas_presenter.dart';
import '../screens/pantalla_alarma_activa.dart';
import '../widgets/banner_ad_widget.dart';
import '../widgets/dialogo_alarma.dart';
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
  bool _modoNoMolestar = false;
  bool _animarFAB = false;
  Alarma? _alarmaRinging;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _presenter = AlarmasPresenter(view: this);
    _presenter.iniciar().catchError((Object e, StackTrace s) {
      debugPrint('Error al iniciar presenter: $e');
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final alarmas = _presenter.alarmas;
      if (alarmas.isEmpty && mounted) {
        setState(() => _animarFAB = true);
      }
    });
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
    if (mounted) setState(() => _animarFAB = false);
  }

  @override
  void onAlarmaActualizada() {
    if (mounted) {
      setState(() {
        // Si la alarma ya no está sonando (detenida externamente), cerrar el banner.
        if (!_presenter.hayAlarmaSonando) {
          _alarmaRinging = null;
        }
      });
    }
  }

  @override
  void onAlarmaEliminada() {
    if (mounted) setState(() => _animarFAB = _presenter.alarmas.isEmpty);
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
          onCerrarConConfirmacion: () => _presenter.cerrarConConfirmacion(alarma), // ← NUEVO
        ),
      ),
    );
  }

  @override
  void onAlarmaSonandoEnForeground(Alarma alarma) {
    if (!mounted) return;
    setState(() => _alarmaRinging = alarma);
  }

  @override
  BuildContext getContext() => context;

  // ─── Acciones del usuario ───────────────────────────────────────

  /// Abre el diálogo unificado para crear una nueva alarma.
  Future<void> _agregarAlarma() async {
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => DialogoAlarma(
        onGuardar: (hora, minuto, etiqueta, dias) async {
          Navigator.pop(ctx);
          await _presenter.agregarAlarma(
            hora: hora,
            minuto: minuto,
            etiqueta: etiqueta.trim().isEmpty ? 'Alarma' : etiqueta.trim(),
            diasSemana: dias,
          );
        },
      ),
    );
  }

  /// Abre el diálogo unificado para editar una alarma existente.
  Future<void> _editarAlarma(Alarma alarma) async {
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => DialogoAlarma(
        alarma: alarma,
        onGuardar: (hora, minuto, etiqueta, dias) async {
          Navigator.pop(ctx);
          await _presenter.actualizarAlarmaCompleta(
            alarma: alarma,
            nuevaHora: hora,
            nuevoMinuto: minuto,
            nuevaEtiqueta: etiqueta,
            nuevosDias: dias,
          );
        },
      ),
    );
  }

  /// Elimina una alarma con opción de deshacer (SnackBar).
  void _eliminarConUndo(Alarma alarma) {
    final copia = alarma.copyWith();

    _presenter.eliminarAlarma(alarma);

    if (!mounted) return;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.inversePrimary),
            const SizedBox(width: 12),
            const Text('Alarma eliminada'),
          ],
        ),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        action: SnackBarAction(
          label: 'Deshacer',
          textColor: Theme.of(context).colorScheme.inversePrimary,
          onPressed: () {
            _presenter.restaurarAlarma(copia);
          },
        ),
      ),
    );
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
    final alarmas = [..._presenter.alarmas]..sort((a, b) {
      if (a.activa != b.activa) return a.activa ? -1 : 1;
      final horaA = a.horaDelDia * 60 + a.minutoDelDia;
      final horaB = b.horaDelDia * 60 + b.minutoDelDia;
      return horaA.compareTo(horaB);
    });
    final proximaTexto = _presenter.obtenerTextoProximaAlarma();
    final hayAlarmas = _presenter.obtenerProximaAlarma() != null;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Mis Alarmas'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // ── Banner: alarma sonando (foreground) ──
          if (_alarmaRinging != null)
            _BannerAlarmaSonando(
              alarma: _alarmaRinging!,
              onVer: () {
                final alarma = _alarmaRinging!;
                setState(() => _alarmaRinging = null);
                onMostrarPantallaAlarma(alarma);
              },
              onDetener: () {
                final alarma = _alarmaRinging!;
                setState(() => _alarmaRinging = null);
                _presenter.detenerAlarma(alarma);
              },
              onPosponer: () {
                final alarma = _alarmaRinging!;
                setState(() => _alarmaRinging = null);
                _presenter.posponerAlarma(alarma);
              },
            ),

          // ── Header: próxima alarma ──
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF0D47A1),
                  Theme.of(context).colorScheme.primary,
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                if (hayAlarmas)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.alarm,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Próxima alarma: $proximaTexto',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.nights_stay_outlined,
                        color: Colors.white.withValues(alpha: 0.8),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        proximaTexto,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 15,
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
                    .withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.4),
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
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.95, end: 1.0),
                          duration: const Duration(milliseconds: 1500),
                          curve: Curves.easeInOut,
                          builder: (context, value, child) {
                            return Transform.scale(
                              scale: value,
                              child: child,
                            );
                          },
                          child: Icon(
                            Icons.alarm_add_outlined,
                            size: 72,
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No tienes alarmas',
                          style: TextStyle(
                            fontSize: 20,
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
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: alarmas.length,
                    itemBuilder: (context, index) {
                      final alarma = alarmas[index];
                      return TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: Duration(milliseconds: 300 + (index * 100)),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) {
                          return Transform.translate(
                            offset: Offset(0, 30 * (1 - value)),
                            child: Opacity(
                              opacity: value,
                              child: child,
                            ),
                          );
                        },
                        child: RepaintBoundary(
                          child: TarjetaAlarma(
                            alarma: alarma,
                            onToggle: (v) {
                              _presenter.toggleAlarma(alarma, v);
                              HapticFeedback.selectionClick();
                            },
                            onEliminar: () => _eliminarConUndo(alarma),
                            onTap: () => _editarAlarma(alarma),
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // ── Banner publicitario al fondo (solo en móvil) ──
          if (Platform.isAndroid || Platform.isIOS)
            const Center(child: BannerAdWidget()),
        ],
      ),
      floatingActionButton: _animarFAB && alarmas.isEmpty
          ? _FABAnimado(onTap: _agregarAlarma)
          : FloatingActionButton.extended(
              onPressed: _agregarAlarma,
              icon: const Icon(Icons.add),
              label: const Text('Nueva alarma'),
              elevation: 4,
            ),
    );
  }
}

/// FAB con animación de pulso sutil para llamar la atención cuando no hay alarmas.
class _FABAnimado extends StatefulWidget {
  final VoidCallback onTap;

  const _FABAnimado({required this.onTap});

  @override
  State<_FABAnimado> createState() => _FABAnimadoState();
}

class _FABAnimadoState extends State<_FABAnimado>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: FloatingActionButton.extended(
        onPressed: widget.onTap,
        icon: const Icon(Icons.add),
        label: const Text('Nueva alarma'),
        elevation: 6,
      ),
    );
  }
}

/// Banner que aparece cuando la alarma suena mientras la app está en primer plano.
///
/// Muestra un aviso sutil en la parte superior con opciones para ver,
/// detener o posponer la alarma. No bloquea la pantalla actual.
class _BannerAlarmaSonando extends StatefulWidget {
  final Alarma alarma;
  final VoidCallback onVer;
  final VoidCallback onDetener;
  final VoidCallback onPosponer;

  const _BannerAlarmaSonando({
    required this.alarma,
    required this.onVer,
    required this.onDetener,
    required this.onPosponer,
  });

  @override
  State<_BannerAlarmaSonando> createState() => _BannerAlarmaSonandoState();
}

class _BannerAlarmaSonandoState extends State<_BannerAlarmaSonando>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  Icons.alarm,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${widget.alarma.etiqueta} está sonando',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: widget.onVer,
                  icon: const Icon(Icons.open_in_full, size: 18),
                  label: const Text('Ver'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.onPosponer,
                    icon: const Icon(Icons.snooze, size: 16),
                    label: const Text('5 min'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: widget.onDetener,
                    icon: const Icon(Icons.stop, size: 16),
                    label: const Text('Detener'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
