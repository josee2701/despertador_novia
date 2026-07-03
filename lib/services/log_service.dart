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
/// El archivo se recorta automáticamente para no crecer sin límite. El recorte
/// es POR LOTES (no en cada escritura): se cuenta en memoria cuántas líneas hay
/// y solo se relee/reescribe el archivo cuando se supera [_maxLineas] + margen.
/// Esto evita una lectura O(n) del archivo completo en cada `registrar`.
///
/// Es un singleton: usar [LogService.instancia].
class LogService {
  LogService._({int maxLineas = 600, int margenRecorte = 100})
      : _maxLineas = maxLineas,
        _margenRecorte = margenRecorte;

  /// Instancia única compartida en toda la app.
  static final LogService instancia = LogService._();

  /// Crea una instancia aislada para pruebas que escribe en [archivo], sin
  /// depender de path_provider. Permite umbrales pequeños para verificar el
  /// comportamiento de recorte sin escribir cientos de líneas.
  @visibleForTesting
  factory LogService.paraPruebas(
    File archivo, {
    int maxLineas = 5,
    int margenRecorte = 2,
  }) {
    final servicio =
        LogService._(maxLineas: maxLineas, margenRecorte: margenRecorte);
    servicio._archivo = archivo;
    return servicio;
  }

  static const String _nombreArchivo = 'diagnostico_alarmas.log';

  /// Máximo de líneas conservadas. Al superarse (+ margen), se recorta.
  final int _maxLineas;

  /// Margen de líneas extra que se permite acumular antes de recortar, para no
  /// releer/reescribir el archivo en cada línea.
  final int _margenRecorte;

  /// Conteo en memoria de líneas del archivo, para decidir el recorte sin leer.
  int _lineasEstimadas = 0;

  /// Si el archivo ya se abrió y se contó su tamaño inicial una vez.
  bool _inicializado = false;

  /// Nº de recortes realizados. Expuesto solo para pruebas de eficiencia.
  int _recortesRealizados = 0;
  @visibleForTesting
  int get recortesRealizados => _recortesRealizados;

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
    if (_inicializado && _archivo != null) return _archivo!;
    // En pruebas, _archivo ya viene fijado; en producción se resuelve aquí.
    final archivo = _archivo ??
        File('${(await getApplicationDocumentsDirectory()).path}/$_nombreArchivo');
    if (!await archivo.exists()) {
      await archivo.create(recursive: true);
    }
    // Conteo inicial una sola vez; luego se mantiene en memoria.
    _lineasEstimadas = (await archivo.readAsLines()).length;
    _archivo = archivo;
    _inicializado = true;
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
        // flush:true por durabilidad: el diagnóstico debe sobrevivir a que el OS
        // mate el proceso justo tras un evento crítico (la última línea importa).
        await archivo.writeAsString('$linea\n',
            mode: FileMode.append, flush: true);
        _lineasEstimadas++;
        // Recorte POR LOTES: solo cuando se supera el máximo + margen, evitando
        // releer todo el archivo en cada escritura.
        if (_lineasEstimadas > _maxLineas + _margenRecorte) {
          await _recortar(archivo);
        }
      } catch (e) {
        debugPrint('LogService.registrar error: $e');
      }
    });
  }

  /// Conserva solo las [_maxLineas] más recientes y actualiza el conteo.
  Future<void> _recortar(File archivo) async {
    try {
      final lineas = await archivo.readAsLines();
      if (lineas.length > _maxLineas) {
        final recortadas = lineas.sublist(lineas.length - _maxLineas);
        await archivo.writeAsString('${recortadas.join('\n')}\n');
        _lineasEstimadas = recortadas.length;
        _recortesRealizados++;
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
