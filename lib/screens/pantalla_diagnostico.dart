import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../services/log_service.dart';
import '../services/permission_service.dart';

/// Pantalla de diagnóstico y soporte.
///
/// Muestra el estado de los permisos críticos (con botones para arreglarlos),
/// una guía específica para fabricantes agresivos (Xiaomi/MIUI, etc.), el
/// registro de eventos con marcas de tiempo, y un botón para compartir un
/// reporte completo (dispositivo + permisos + log) por WhatsApp/email.
class PantallaDiagnostico extends StatefulWidget {
  const PantallaDiagnostico({super.key});

  @override
  State<PantallaDiagnostico> createState() => _PantallaDiagnosticoState();
}

class _PantallaDiagnosticoState extends State<PantallaDiagnostico>
    with WidgetsBindingObserver {
  final _permisos = PermissionService();

  /// Controller propio para el log: el Scrollbar con thumbVisibility lo exige
  /// al estar anidado dentro del ListView (no hay PrimaryScrollController).
  final _logScroll = ScrollController();

  static const _verdeOk = Color(0xFF2E7D32);
  static const _naranjaOEM = Color(0xFFE65100);

  EstadoPermisos? _estado;
  String _dispositivo = '';
  String _versionApp = '';
  String _log = '';
  bool _esOEMAgresivo = false;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cargarTodo();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _logScroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver de los ajustes del sistema, refrescar el estado de permisos.
    if (state == AppLifecycleState.resumed) _cargarTodo();
  }

  Future<void> _cargarTodo() async {
    final estado = await _permisos.obtenerEstadoPermisos();
    final dispositivo = await _permisos.descripcionDispositivo();
    final oem = await _permisos.esFabricanteAgresivo();
    final log = await LogService.instancia.leerLog();
    String version = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version}+${info.buildNumber}';
    } catch (_) {
      version = 'desconocida';
    }
    if (!mounted) return;
    setState(() {
      _estado = estado;
      _dispositivo = dispositivo;
      _esOEMAgresivo = oem;
      _log = log;
      _versionApp = version;
      _cargando = false;
    });
  }

  String _construirReporte() {
    final ahora = DateTime.now();
    final estado = _estado;
    return '=== REPORTE MI DESPERTADOR ===\n'
        'App: $_versionApp\n'
        'Dispositivo: $_dispositivo\n'
        'Fecha del reporte: $ahora\n\n'
        '--- PERMISOS ---\n'
        '${estado?.resumenTexto ?? "No disponible"}\n\n'
        '--- REGISTRO DE EVENTOS ---\n'
        '$_log';
  }

  Future<void> _compartirReporte() async {
    await SharePlus.instance.share(
      ShareParams(
        text: _construirReporte(),
        subject: 'Reporte Mi Despertador — $_dispositivo',
      ),
    );
  }

  Future<void> _copiarLog() async {
    await Clipboard.setData(ClipboardData(text: _construirReporte()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reporte copiado al portapapeles')),
    );
  }

  Future<void> _limpiarLog() async {
    await LogService.instancia.limpiar();
    await _cargarTodo();
  }

  // ─── Acciones de permisos ───────────────────────────────────────

  Future<void> _arreglarAlarmasExactas() async {
    await _permisos.verificarYSolicitarPermisoAlarmasExactas();
    await _cargarTodo();
  }

  Future<void> _arreglarNotificaciones() async {
    await _permisos.solicitarPermisoNotificaciones();
    await _cargarTodo();
  }

  Future<void> _arreglarBateria() async {
    await _permisos.solicitarExencionBateria();
    await _cargarTodo();
  }

  Future<void> _arreglarFullScreen() async {
    await _permisos.abrirAjustesFullScreenIntent();
  }

  // ─── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Diagnóstico'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _cargarTodo,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _tarjetaResumen(),
                _tituloSeccion('Permisos', primero: true),
                ..._tarjetasPermisos(),
                if (_esOEMAgresivo) ...[
                  _tituloSeccion('Tu teléfono necesita pasos extra'),
                  _guiaOEM(),
                ],
                _tituloSeccion('Registro de eventos'),
                _consolaLog(),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _limpiarLog,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Limpiar registro'),
                  ),
                ),
                const SizedBox(height: 16),
                _botonCompartir(),
              ],
            ),
    );
  }

  Widget _tituloSeccion(String texto, {bool primero = false}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4, primero ? 8 : 24, 4, 12),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.grey[800],
        ),
      ),
    );
  }

  Widget _tarjetaResumen() {
    final todoOk = _estado?.todoCorrecto ?? false;
    final color1 = todoOk ? _verdeOk : const Color(0xFFC62828);
    final color2 = todoOk ? const Color(0xFF43A047) : const Color(0xFFE53935);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color1, color2],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color1.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            todoOk ? Icons.verified_rounded : Icons.error_rounded,
            color: Colors.white,
            size: 40,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  todoOk ? 'Todo en orden' : 'Atención necesaria',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  todoOk
                      ? 'Tus alarmas deberían sonar correctamente'
                      : 'Revisa los permisos marcados en rojo',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _dispositivo,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _tarjetasPermisos() {
    final e = _estado;
    if (e == null) return const [];
    return [
      _tarjetaPermiso(
        icono: Icons.alarm_on,
        titulo: 'Alarmas exactas',
        descripcion: 'Necesario para que la alarma suene a la hora exacta.',
        concedido: e.alarmasExactas,
        onArreglar: _arreglarAlarmasExactas,
      ),
      _tarjetaPermiso(
        icono: Icons.notifications_active,
        titulo: 'Notificaciones',
        descripcion: 'Sin esto no aparece el aviso de la alarma.',
        concedido: e.notificaciones,
        onArreglar: _arreglarNotificaciones,
      ),
      _tarjetaPermiso(
        icono: Icons.battery_charging_full,
        titulo: 'Sin optimización de batería',
        descripcion: 'Evita que el sistema mate la app y la alarma no suene.',
        concedido: e.exencionBateria,
        onArreglar: _arreglarBateria,
      ),
      _tarjetaPermiso(
        icono: Icons.fullscreen,
        titulo: 'Pantalla completa en bloqueo',
        descripcion: 'Necesario para ver la alarma con el teléfono bloqueado.',
        concedido: e.fullScreenIntent,
        onArreglar: _arreglarFullScreen,
      ),
      if (e.noMolestar)
        _tarjetaPermiso(
          icono: Icons.do_not_disturb_on,
          titulo: 'Modo No Molestar activo',
          descripcion: 'Está activado y podría silenciar tu alarma.',
          concedido: false,
          textoBoton: 'Ajustes',
          onArreglar: () => _permisos.abrirConfiguracion(),
        ),
    ];
  }

  Widget _tarjetaPermiso({
    required IconData icono,
    required String titulo,
    required String descripcion,
    required bool concedido,
    required VoidCallback onArreglar,
    String textoBoton = 'Activar',
  }) {
    final rojo = Theme.of(context).colorScheme.error;
    final colorEstado = concedido ? _verdeOk : rojo;

    return Card(
      elevation: 2,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      surfaceTintColor: Theme.of(context).colorScheme.surfaceTint,
      shadowColor: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorEstado.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icono, color: colorEstado, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          titulo,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        concedido ? Icons.check_circle : Icons.cancel,
                        color: colorEstado,
                        size: 18,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    concedido ? 'Concedido' : descripcion,
                    style: TextStyle(
                      fontSize: 13,
                      color: concedido ? _verdeOk : Colors.grey[700],
                      fontWeight:
                          concedido ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!concedido)
              FilledButton(
                onPressed: onArreglar,
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(textoBoton),
              ),
          ],
        ),
      ),
    );
  }

  Widget _guiaOEM() {
    return Card(
      elevation: 0,
      color: const Color(0xFFFFF3E0),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.orange.withValues(alpha: 0.35)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: const Icon(Icons.phone_android,
              color: _naranjaOEM, size: 26),
          title: const Text(
            'Pasos extra para tu teléfono',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _naranjaOEM,
            ),
          ),
          subtitle: const Text(
            'Tu marca cierra apps para ahorrar batería',
            style: TextStyle(fontSize: 12, color: Color(0xFF8D6E63)),
          ),
          iconColor: _naranjaOEM,
          collapsedIconColor: _naranjaOEM,
          children: [
            _pasoGuia(1,
                'Activa "Inicio automático" para esta app (clave: sin esto la alarma no suena tras un rato).'),
            _pasoGuia(2,
                'En el ahorro de batería de la app, elige "Sin restricciones".'),
            _pasoGuia(3,
                'En Recientes, mantén pulsada la app y toca el candado para fijarla en memoria.'),
            _pasoGuia(4,
                'Activa "Mostrar en pantalla de bloqueo" y "Ventanas emergentes" en los permisos de la app.'),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () => _permisos.abrirAutostartOEM(),
                    icon: const Icon(Icons.rocket_launch_outlined, size: 18),
                    label: const Text('Inicio automático'),
                    style: TextButton.styleFrom(foregroundColor: _naranjaOEM),
                  ),
                  TextButton.icon(
                    onPressed: () => _permisos.abrirConfiguracion(),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Ajustes de la app'),
                    style: TextButton.styleFrom(foregroundColor: _naranjaOEM),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pasoGuia(int numero, String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: _naranjaOEM,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$numero',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _consolaLog() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 280),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Scrollbar(
        controller: _logScroll,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _logScroll,
          child: SelectableText(
            _log,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.4,
              color: Color(0xFFE0E0E0),
            ),
          ),
        ),
      ),
    );
  }

  Widget _botonCompartir() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _compartirReporte,
            icon: const Icon(Icons.share_outlined),
            label: const Text('Compartir reporte'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _copiarLog,
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copiar reporte'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}
