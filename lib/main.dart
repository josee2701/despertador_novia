import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:do_not_disturb/do_not_disturb.dart';

// Nombre del archivo de audio generado localmente
const _archivoSonido = 'alarma_limpieza.wav';

// 1=Lunes … 7=Domingo, igual que DateTime.weekday
const _nombresDias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

/// Devuelve la próxima DateTime en que debe dispararse la alarma.
/// Si [diasSemana] está vacío, es una alarma de una sola vez.
DateTime _proximaFecha(int hora, int minuto, List<int> diasSemana) {
  final ahora = DateTime.now();
  final base = DateTime(ahora.year, ahora.month, ahora.day, hora, minuto);
  if (diasSemana.isEmpty) {
    return base.isBefore(ahora) ? base.add(const Duration(days: 1)) : base;
  }
  for (var i = 0; i < 7; i++) {
    final candidato = base.add(Duration(days: i));
    if (diasSemana.contains(candidato.weekday) && candidato.isAfter(ahora)) {
      return candidato;
    }
  }
  return base.add(const Duration(days: 7)); // no debería alcanzarse
}

// Se establece en main() antes de Alarm.init(); el widget lo lee en initState.
bool _necesitaPermisoAlarmasExactas = false;

/// Comprueba si la app puede programar alarmas exactas en Android 12+.
/// Si no tiene permiso, marca el flag para que la UI muestre el diálogo.
Future<void> _verificarPermisoAlarmasExactas() async {
  if (!Platform.isAndroid) return;
  final concedido = await Permission.scheduleExactAlarm.isGranted;
  if (!concedido) {
    _necesitaPermisoAlarmasExactas = true;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _prepararSonido();
  await _verificarPermisoAlarmasExactas();
  await Alarm.init();
  runApp(const MiDespertadorApp());
}

/// Genera el WAV de barrido la primera vez y lo guarda en Documents.
Future<void> _prepararSonido() async {
  final dir = await getApplicationDocumentsDirectory();
  final archivo = File('${dir.path}/$_archivoSonido');
  if (!archivo.existsSync()) {
    await archivo.writeAsBytes(_generarWavBarrido());
  }
}

/// Crea un WAV mono 16-bit con barrido de frecuencias 200 Hz → 1 000 Hz (3 s).
/// El efecto vibra la membrana del parlante similar a los "limpiadores de altavoz".
Uint8List _generarWavBarrido() {
  const sampleRate = 44100;
  const duracion = 3; // segundos
  const numMuestras = sampleRate * duracion;

  final pcm = Int16List(numMuestras);
  for (var i = 0; i < numMuestras; i++) {
    final t = i / sampleRate.toDouble();
    // Barrido lineal de 200 Hz a 1000 Hz
    final freq = 200.0 + 800.0 * (t / duracion);
    pcm[i] = (sin(2 * pi * freq * t) * 32767).toInt().clamp(-32768, 32767);
  }

  final dataSize = numMuestras * 2;
  final b = BytesBuilder();

  void u32(int v) {
    b.addByte(v & 0xFF);
    b.addByte((v >> 8) & 0xFF);
    b.addByte((v >> 16) & 0xFF);
    b.addByte((v >> 24) & 0xFF);
  }

  void u16(int v) {
    b.addByte(v & 0xFF);
    b.addByte((v >> 8) & 0xFF);
  }

  void str(String s) => b.add(s.codeUnits);

  // Cabecera RIFF/WAVE
  str('RIFF');
  u32(36 + dataSize);
  str('WAVE');
  // Bloque fmt
  str('fmt ');
  u32(16);
  u16(1);
  u16(1); // PCM, mono
  u32(sampleRate);
  u32(sampleRate * 2);
  u16(2);
  u16(16);
  // Bloque data
  str('data');
  u32(dataSize);
  for (var i = 0; i < numMuestras; i++) {
    u16(pcm[i] & 0xFFFF);
  }

  return b.toBytes();
}

// ---------------------------------------------------------------------------

class MiDespertadorApp extends StatelessWidget {
  const MiDespertadorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mi Despertador',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 68, 1, 255),
        ),
      ),
      home: const PantallaAlarmas(),
    );
  }
}

class _Alarma {
  final int id;
  DateTime hora;
  String etiqueta;
  bool activa = true;
  bool pospuesta = false;
  List<int> diasSemana;

  _Alarma({
    required this.id,
    required this.hora,
    required this.etiqueta,
    List<int>? diasSemana,
  }) : diasSemana = diasSemana ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'hora': hora.toIso8601String(),
    'etiqueta': etiqueta,
    'activa': activa,
    'pospuesta': pospuesta,
    'diasSemana': diasSemana,
  };

  factory _Alarma.fromJson(Map<String, dynamic> json) {
    final alarma = _Alarma(
      id: json['id'] as int,
      hora: DateTime.parse(json['hora'] as String),
      etiqueta: json['etiqueta'] as String,
      diasSemana: (json['diasSemana'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          [],
    );
    alarma.activa = json['activa'] as bool;
    alarma.pospuesta = (json['pospuesta'] as bool?) ?? false;
    return alarma;
  }
}

class PantallaAlarmas extends StatefulWidget {
  const PantallaAlarmas({super.key});

  @override
  State<PantallaAlarmas> createState() => _PantallaAlarmasState();
}

class _PantallaAlarmasState extends State<PantallaAlarmas>
    with WidgetsBindingObserver {
  final List<_Alarma> _alarmas = [];
  int _nextId = 1;
  bool _modoNoMolestar = false;
  final _dndPlugin = DoNotDisturbPlugin();
  DateTime _ahora = DateTime.now();
  late Timer _timer;
  late StreamSubscription<AlarmSet> _suscripcion;
  AlarmSet _prevAlarmSet = AlarmSet.empty();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _ahora = DateTime.now()),
    );
    _suscripcion = Alarm.ringing.listen(_mostrarDialogoAlarma);
    _cargarAlarmas();
    _verificarModoNoMolestar();
    if (_necesitaPermisoAlarmasExactas) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _mostrarDialogoPermisoAlarma(),
      );
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _suscripcion.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _verificarModoNoMolestar();
    }
  }

  Future<void> _verificarModoNoMolestar() async {
    if (!Platform.isAndroid) return;
    final activo = await _dndPlugin.isDndEnabled();
    if (mounted && activo != _modoNoMolestar) {
      setState(() => _modoNoMolestar = activo);
    }
  }

  Future<void> _guardarAlarmas() async {
    final prefs = await SharedPreferences.getInstance();
    final lista = _alarmas.map((a) => jsonEncode(a.toJson())).toList();
    await prefs.setStringList('alarmas', lista);
    await prefs.setInt('nextId', _nextId);
  }

  Future<void> _cargarAlarmas() async {
    final prefs = await SharedPreferences.getInstance();
    final lista = prefs.getStringList('alarmas') ?? [];
    final ahora = DateTime.now();
    var huboCambios = false;
    for (final entrada in lista) {
      final alarma = _Alarma.fromJson(
        jsonDecode(entrada) as Map<String, dynamic>,
      );
      // Alarma vencida: calcular la próxima fecha y reprogramar
      if (alarma.activa && alarma.hora.isBefore(ahora)) {
        alarma.hora = alarma.diasSemana.isEmpty
            // Una sola vez: mover al día siguiente a la misma hora
            ? DateTime(ahora.year, ahora.month, ahora.day,
                    alarma.hora.hour, alarma.hora.minute)
                .add(const Duration(days: 1))
            // Recurrente: próxima ocurrencia según los días configurados
            : _proximaFecha(
                alarma.hora.hour, alarma.hora.minute, alarma.diasSemana);
        huboCambios = true;
      }
      if (alarma.activa && alarma.hora.isAfter(ahora)) {
        await Alarm.set(alarmSettings: _crearConfiguracion(alarma));
      }
      _alarmas.add(alarma);
    }
    _nextId = prefs.getInt('nextId') ??
        (_alarmas.isEmpty
            ? 1
            : _alarmas.map((a) => a.id).reduce(max) + 1);
    if (huboCambios) await _guardarAlarmas();
    if (mounted) setState(() {});
  }

  AlarmSettings _crearConfiguracion(_Alarma alarma) {
    return AlarmSettings(
      id: alarma.id,
      dateTime: alarma.hora,
      // Ruta relativa al directorio Documents del dispositivo
      assetAudioPath: _archivoSonido,
      // Volumen al 100% forzado: no se puede bajar mientras suena
      volumeSettings: const VolumeSettings.fixed(
        volume: 1.0,
        volumeEnforced: true,
      ),
      notificationSettings: NotificationSettings(
        title: 'Mi Despertador',
        body: alarma.etiqueta,
        stopButton: 'Detener alarma',
      ),
      loopAudio: true,
      vibrate: true,
      androidFullScreenIntent: true,
      warningNotificationOnKill: false,
    );
  }

  Future<void> _agregarAlarma() async {
    final TimeOfDay? horaElegida = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (horaElegida == null || !mounted) return;

    final etiquetaIngresada = await _pedirEtiqueta('');
    if (etiquetaIngresada == null || !mounted) return;

    final diasElegidos = await _pedirDiasSemana([]);
    if (diasElegidos == null || !mounted) return;

    final nuevaAlarma = _Alarma(
      id: _nextId++,
      hora: _proximaFecha(horaElegida.hour, horaElegida.minute, diasElegidos),
      etiqueta: etiquetaIngresada.trim().isEmpty ? 'Alarma' : etiquetaIngresada.trim(),
      diasSemana: diasElegidos,
    );

    await Alarm.set(alarmSettings: _crearConfiguracion(nuevaAlarma));
    setState(() => _alarmas.add(nuevaAlarma));
    await _guardarAlarmas();
  }

  Future<void> _toggleAlarma(_Alarma alarma, bool activa) async {
    if (activa) {
      await Alarm.set(alarmSettings: _crearConfiguracion(alarma));
    } else {
      await Alarm.stop(alarma.id);
    }
    setState(() => alarma.activa = activa);
    await _guardarAlarmas();
  }

  Future<void> _eliminarAlarma(_Alarma alarma) async {
    await Alarm.stop(alarma.id);
    setState(() => _alarmas.remove(alarma));
    await _guardarAlarmas();
  }

  /// Muestra un diálogo con un TextField para ingresar o editar una etiqueta.
  /// Devuelve el texto introducido, o null si el usuario cancela.
  Future<String?> _pedirEtiqueta(String inicial) async {
    if (!mounted) return null;
    final controller = TextEditingController(text: inicial);
    final resultado = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nombre de la alarma'),
        content: TextField(
          controller: controller,
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
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    // Diferir el dispose al siguiente frame para que el diálogo termine
    // de animar su salida antes de que el controlador sea liberado.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    return resultado;
  }

  /// Muestra un diálogo para elegir los días de repetición.
  /// Devuelve la lista ordenada (puede estar vacía = una sola vez), o null si cancela.
  Future<List<int>?> _pedirDiasSemana(List<int> inicial) async {
    if (!mounted) return null;
    var seleccionados = List<int>.from(inicial);
    return showDialog<List<int>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Repetir alarma'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Acceso rápido',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  ActionChip(
                    label: const Text('Lun–Vie'),
                    onPressed: () =>
                        setLocal(() => seleccionados = [1, 2, 3, 4, 5]),
                  ),
                  ActionChip(
                    label: const Text('Todos los días'),
                    onPressed: () =>
                        setLocal(() => seleccionados = [1, 2, 3, 4, 5, 6, 7]),
                  ),
                  ActionChip(
                    label: const Text('Solo fin de semana'),
                    onPressed: () =>
                        setLocal(() => seleccionados = [6, 7]),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: List.generate(7, (i) {
                  final dia = i + 1;
                  return FilterChip(
                    label: Text(_nombresDias[i]),
                    selected: seleccionados.contains(dia),
                    onSelected: (v) => setLocal(() {
                      if (v) {
                        seleccionados.add(dia);
                        seleccionados.sort();
                      } else {
                        seleccionados.remove(dia);
                      }
                    }),
                  );
                }),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sin días seleccionados = alarma de una sola vez',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, seleccionados),
              child: const Text('Listo'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editarEtiqueta(_Alarma alarma) async {
    final nueva = await _pedirEtiqueta(alarma.etiqueta);
    if (nueva == null || !mounted) return;
    setState(() => alarma.etiqueta = nueva.trim().isEmpty ? 'Alarma' : nueva.trim());
    if (alarma.activa) {
      await Alarm.set(alarmSettings: _crearConfiguracion(alarma));
    }
    await _guardarAlarmas();
  }

  Future<void> _editarHora(_Alarma alarma) async {
    final nueva = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: alarma.hora.hour, minute: alarma.hora.minute),
    );
    if (nueva == null || !mounted) return;

    final ahora = DateTime.now();
    DateTime fechaNueva = DateTime(
      ahora.year, ahora.month, ahora.day, nueva.hour, nueva.minute,
    );
    if (fechaNueva.isBefore(ahora)) {
      fechaNueva = fechaNueva.add(const Duration(days: 1));
    }

    setState(() => alarma.hora = fechaNueva);
    if (alarma.activa) {
      await Alarm.set(alarmSettings: _crearConfiguracion(alarma));
    }
    await _guardarAlarmas();

    if (mounted) {
      final horaStr =
          '${fechaNueva.hour.toString().padLeft(2, '0')}:${fechaNueva.minute.toString().padLeft(2, '0')}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Alarma actualizada para las $horaStr')),
      );
    }
  }

  /// Explica al usuario por qué se necesita el permiso y abre Configuración.
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
              await openAppSettings();
            },
            child: const Text('Ir a Configuración'),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoAlarma(AlarmSet conjunto) {
    if (!mounted) return;
    for (final configuracion in conjunto.alarms) {
      // Solo abrir diálogo para alarmas que acaban de añadirse al set
      if (_prevAlarmSet.containsId(configuracion.id)) continue;

      final alarma = _alarmas.where((a) => a.id == configuracion.id).firstOrNull;
      if (alarma != null) {
        setState(() => alarma.pospuesta = false);
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('¡Alarma!'),
          content: Text(configuracion.notificationSettings.body),
          actions: [
            TextButton(
              onPressed: () async {
                await Alarm.stop(configuracion.id);
                final a = _alarmas.where((a) => a.id == configuracion.id).firstOrNull;
                if (a != null) {
                  setState(() {
                    a.hora = DateTime.now().add(const Duration(minutes: 5));
                    a.pospuesta = true;
                  });
                  await Alarm.set(alarmSettings: _crearConfiguracion(a));
                  await _guardarAlarmas();
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Posponer 5 min'),
            ),
            FilledButton(
              onPressed: () async {
                await Alarm.stop(configuracion.id);
                final a = _alarmas.where((a) => a.id == configuracion.id).firstOrNull;
                if (a != null) {
                  a.pospuesta = false;
                  if (a.diasSemana.isNotEmpty) {
                    a.hora = _proximaFecha(
                        a.hora.hour, a.hora.minute, a.diasSemana);
                    await Alarm.set(alarmSettings: _crearConfiguracion(a));
                  }
                  setState(() {});
                  await _guardarAlarmas();
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Detener'),
            ),
          ],
        ),
      );
    }
    _prevAlarmSet = conjunto;
  }

  String _formatearHora(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _periodo(DateTime dt) => dt.hour < 12 ? 'AM' : 'PM';

  String _horaActualHHMMSS() {
    final h = _ahora.hour.toString().padLeft(2, '0');
    final m = _ahora.minute.toString().padLeft(2, '0');
    final s = _ahora.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _textoProximaAlarma() {
    final candidatas = _alarmas
        .where((a) => a.activa && a.hora.isAfter(_ahora))
        .toList()
      ..sort((a, b) => a.hora.compareTo(b.hora));

    if (candidatas.isEmpty) return 'No hay alarmas programadas';

    final proxima = candidatas.first;
    final diff = proxima.hora.difference(_ahora);
    final horas = diff.inHours;
    final minutos = diff.inMinutes.remainder(60);

    final tiempoStr = horas > 0 ? '${horas}h ${minutos}min' : '${minutos}min';
    return 'Próxima alarma: ${proxima.etiqueta} en $tiempoStr';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Mis Alarmas'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Text(
                  _horaActualHHMMSS(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 52,
                    fontWeight: FontWeight.w200,
                    letterSpacing: 4,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _textoProximaAlarma(),
                  style: TextStyle(
                    color: Colors.white.withAlpha(210),
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          if (_modoNoMolestar)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF9C4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFF9A825)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Color(0xFFF57F17), size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Modo No Molestar activo — Tu alarma podría no sonar',
                      style: TextStyle(
                        color: Color(0xFF5D4037),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _alarmas.isEmpty
                ? const Center(
                    child: Text(
                      'No hay alarmas\nPresiona + para agregar una',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16.0),
              itemCount: _alarmas.length,
              itemBuilder: (context, index) {
                final alarma = _alarmas[index];
                return Dismissible(
                  key: ValueKey(alarma.id),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => _eliminarAlarma(alarma),
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
                    elevation: 0,
                    color: alarma.activa ? Colors.white : Colors.grey[200],
                    margin: const EdgeInsets.only(bottom: 12.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: ListTile(
                        title: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              _formatearHora(alarma.hora),
                              style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w300,
                                color: alarma.activa
                                    ? Colors.black
                                    : Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _periodo(alarma.hora),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: alarma.activa
                                    ? Colors.black
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
                                  Icons.notifications,
                                  size: 16,
                                  color: alarma.activa
                                      ? Colors.grey[600]
                                      : Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  alarma.etiqueta,
                                  style: TextStyle(
                                    color: alarma.activa
                                        ? Colors.grey[600]
                                        : Colors.grey,
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
                                        _nombresDias[i],
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: activo
                                              ? FontWeight.w700
                                              : FontWeight.normal,
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
                            PopupMenuButton<String>(
                              icon: Icon(
                                Icons.more_vert,
                                color: alarma.activa
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Colors.grey,
                              ),
                              onSelected: (opcion) {
                                if (opcion == 'nombre') {
                                  _editarEtiqueta(alarma);
                                } else if (opcion == 'hora') {
                                  _editarHora(alarma);
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'nombre',
                                  child: ListTile(
                                    leading: Icon(Icons.edit),
                                    title: Text('Editar nombre'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'hora',
                                  child: ListTile(
                                    leading: Icon(Icons.access_time),
                                    title: Text('Editar hora'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ],
                            ),
                            Switch(
                              value: alarma.activa,
                              onChanged: (v) => _toggleAlarma(alarma, v),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
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
