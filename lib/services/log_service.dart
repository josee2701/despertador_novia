import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Servicio de registro persistente para diagnóstico en dispositivos reales.
///
/// Escribe eventos con marca de tiempo a un archivo en el directorio de
/// documentos. Sirve para detectar el momento exacto en que una alarma falla:
/// si se registra "programada" pero nunca "DISPARÓ", el sistema mató la app.
///
/// El archivo se recorta automáticamente para no crecer sin límite.
/// Es un singleton: usar [LogService.instancia].
class LogService {
  LogService._();

  /// Instancia única compartida en toda la app.
  static final LogService instancia = LogService._();

  static const String _nombreArchivo = 'diagnostico_alarmas.log';

  /// Máximo de líneas conservadas. Al superarse, se descartan las más antiguas.
  static const int _maxLineas = 600;

  File? _archivo;

  /// Cola que serializa todas las operaciones de E/S sobre el archivo.
  ///
  /// Sin esto, varios [registrar] concurrentes (p. ej. fallos de anuncios cada
  /// pocos segundos a la vez que el arranque) intercalan append y reescritura
  /// del recorte, corrompiendo líneas. La cola garantiza una operación a la vez.
  Future<void> _cola = Future.value();

  /// Encola [accion] tras las operaciones pendientes y devuelve su resultado.
  Future<T> _encolar<T>(Future<T> Function() accion) {
    final completer = Completer<T>();
    _cola = _cola.then((_) async {
      try {
        completer.complete(await accion());
      } catch (e) {
        completer.completeError(e);
      }
    });
    return completer.future;
  }

  Future<File> _obtenerArchivo() async {
    if (_archivo != null) return _archivo!;
    final dir = await getApplicationDocumentsDirectory();
    final archivo = File('${dir.path}/$_nombreArchivo');
    if (!await archivo.exists()) {
      await archivo.create(recursive: true);
    }
    _archivo = archivo;
    return archivo;
  }

  String _marcaTiempo() {
    final ahora = DateTime.now();
    String dos(int n) => n.toString().padLeft(2, '0');
    String tres(int n) => n.toString().padLeft(3, '0');
    // Incluye año (los reportes cruzan meses) y milisegundos (para medir el gap
    // real entre "DISPARÓ" y "detenida"; 1-2s redondeado no basta para diagnosticar).
    return '${dos(ahora.day)}/${dos(ahora.month)}/${ahora.year} '
        '${dos(ahora.hour)}:${dos(ahora.minute)}:${dos(ahora.second)}'
        '.${tres(ahora.millisecond)}';
  }

  /// Registra un [evento] con marca de tiempo. Nunca lanza excepciones.
  Future<void> registrar(String evento) {
    final linea = '[${_marcaTiempo()}] $evento';
    debugPrint('DIAG: $linea');
    return _encolar(() async {
      try {
        final archivo = await _obtenerArchivo();
        await archivo.writeAsString('$linea\n',
            mode: FileMode.append, flush: true);
        await _recortarSiHaceFalta(archivo);
      } catch (e) {
        debugPrint('LogService.registrar error: $e');
      }
    });
  }

  /// Si el archivo supera [_maxLineas], conserva solo las más recientes.
  Future<void> _recortarSiHaceFalta(File archivo) async {
    try {
      final lineas = await archivo.readAsLines();
      if (lineas.length > _maxLineas) {
        final recortadas = lineas.sublist(lineas.length - _maxLineas);
        await archivo.writeAsString('${recortadas.join('\n')}\n');
      }
    } catch (_) {
      // No interrumpir el flujo por un fallo de recorte.
    }
  }

  /// Devuelve todo el contenido del registro, del más antiguo al más reciente.
  Future<String> leerLog() {
    return _encolar(() async {
      try {
        final archivo = await _obtenerArchivo();
        final contenido = await archivo.readAsString();
        return contenido.trim().isEmpty
            ? 'Sin eventos registrados todavía.'
            : contenido;
      } catch (e) {
        return 'No se pudo leer el registro: $e';
      }
    });
  }

  /// Borra todo el registro.
  Future<void> limpiar() {
    return _encolar(() async {
      try {
        final archivo = await _obtenerArchivo();
        await archivo.writeAsString('');
      } catch (e) {
        debugPrint('LogService.limpiar error: $e');
      }
    });
  }
}
