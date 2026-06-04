import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/constantes.dart';

/// Servicio encargado de generar y gestionar el archivo de audio de la alarma.
///
/// Crea un WAV con barrido de frecuencias (200Hz → 1000Hz durante 3 segundos)
/// que produce un efecto de vibración en el parlante, similar a los
/// "limpiadores de altavoz". El archivo se genera una sola vez y se guarda
/// en el directorio Documents del dispositivo.
class AudioService {
  /// Genera el archivo WAV si no existe ya en el sistema.
  Future<void> prepararSonido() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final archivo = File('${dir.path}/$archivoSonido');
      if (!archivo.existsSync()) {
        await archivo.writeAsBytes(_generarWavBarrido());
      }
    } catch (e) {
      debugPrint('AudioService: no se pudo generar el audio de alarma: $e');
    }
  }

  /// Crea un WAV mono 16-bit con barrido de frecuencias 200 Hz → 1 000 Hz.
  Uint8List _generarWavBarrido() {
    const sampleRate = 44100;
    const duracion = 3;
    const numMuestras = sampleRate * duracion;

    final pcm = Int16List(numMuestras);
    for (var i = 0; i < numMuestras; i++) {
      final t = i / sampleRate.toDouble();
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
    str('fmt ');
    u32(16);
    u16(1);
    u16(1); // PCM, mono
    u32(sampleRate);
    u32(sampleRate * 2);
    u16(2);
    u16(16);
    str('data');
    u32(dataSize);
    for (var i = 0; i < numMuestras; i++) {
      u16(pcm[i] & 0xFFFF);
    }

    return b.toBytes();
  }
}
