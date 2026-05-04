import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

// Nombre del archivo de audio generado localmente
const _archivoSonido = 'alarma_limpieza.wav';

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
  final DateTime hora;
  final String etiqueta;
  bool activa = true;

  _Alarma({required this.id, required this.hora, required this.etiqueta});
}

class PantallaAlarmas extends StatefulWidget {
  const PantallaAlarmas({super.key});

  @override
  State<PantallaAlarmas> createState() => _PantallaAlarmasState();
}

class _PantallaAlarmasState extends State<PantallaAlarmas> {
  final List<_Alarma> _alarmas = [];

  // ignore: deprecated_member_use
  late StreamSubscription<AlarmSettings> _suscripcion;

  @override
  void initState() {
    super.initState();
    // ignore: deprecated_member_use
    _suscripcion = Alarm.ringStream.stream.listen(_mostrarDialogoAlarma);
    if (_necesitaPermisoAlarmasExactas) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _mostrarDialogoPermisoAlarma(),
      );
    }
  }

  @override
  void dispose() {
    _suscripcion.cancel();
    super.dispose();
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

    final ahora = DateTime.now();
    DateTime fechaAlarma = DateTime(
      ahora.year,
      ahora.month,
      ahora.day,
      horaElegida.hour,
      horaElegida.minute,
    );
    if (fechaAlarma.isBefore(ahora)) {
      fechaAlarma = fechaAlarma.add(const Duration(days: 1));
    }

    final nuevaAlarma = _Alarma(
      id: Random().nextInt(2147483646) + 1,
      hora: fechaAlarma,
      etiqueta: 'Alarma',
    );

    await Alarm.set(alarmSettings: _crearConfiguracion(nuevaAlarma));
    setState(() => _alarmas.add(nuevaAlarma));
  }

  Future<void> _toggleAlarma(_Alarma alarma, bool activa) async {
    if (activa) {
      await Alarm.set(alarmSettings: _crearConfiguracion(alarma));
    } else {
      await Alarm.stop(alarma.id);
    }
    setState(() => alarma.activa = activa);
  }

  Future<void> _eliminarAlarma(_Alarma alarma) async {
    await Alarm.stop(alarma.id);
    setState(() => _alarmas.remove(alarma));
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

  void _mostrarDialogoAlarma(AlarmSettings configuracion) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('¡Alarma!'),
        content: Text(configuracion.notificationSettings.body),
        actions: [
          FilledButton(
            onPressed: () async {
              await Alarm.stop(configuracion.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Detener'),
          ),
        ],
      ),
    );
  }

  String _formatearHora(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _periodo(DateTime dt) => dt.hour < 12 ? 'AM' : 'PM';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Mis Alarmas'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: _alarmas.isEmpty
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
                        subtitle: Row(
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
                        trailing: Switch(
                          value: alarma.activa,
                          onChanged: (v) => _toggleAlarma(alarma, v),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _agregarAlarma,
        child: const Icon(Icons.add),
      ),
    );
  }
}
