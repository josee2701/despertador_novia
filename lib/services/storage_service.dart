import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/alarma.dart';
import '../utils/constantes.dart';

/// Servicio de persistencia para alarmas usando SharedPreferences.
///
/// Encapsula toda la lógica de lectura y escritura del almacenamiento local,
/// de modo que el resto de la app no necesita conocer los detalles de
/// serialización o las claves utilizadas.
class StorageService {
  /// Guarda la lista completa de alarmas y el siguiente ID disponible.
  ///
  /// Cada alarma se serializa como JSON individual y se almacena como
  /// una lista de strings.
  Future<void> guardarAlarmas(List<Alarma> alarmas, int nextId) async {
    final prefs = await SharedPreferences.getInstance();
    final lista = alarmas.map((a) => jsonEncode(a.toJson())).toList();
    await prefs.setStringList(claveAlarmas, lista);
    await prefs.setInt(claveNextId, nextId);
  }

  /// Carga todas las alarmas almacenadas y el siguiente ID disponible.
  ///
  /// Retorna un mapa con las alarmas decodificadas y el valor de nextId.
  /// Si no hay datos almacenados, devuelve listas vacías.
  Future<({List<Alarma> alarmas, int nextId})> cargarAlarmas() async {
    final prefs = await SharedPreferences.getInstance();
    final lista = prefs.getStringList(claveAlarmas) ?? [];
    final alarmas = <Alarma>[];

    for (final entrada in lista) {
      try {
        final datos = jsonDecode(entrada) as Map<String, dynamic>;
        alarmas.add(Alarma.fromJson(datos));
      } catch (_) {
        // Ignorar entradas corruptas individualmente
      }
    }

    final nextId = prefs.getInt(claveNextId) ??
        (alarmas.isEmpty ? 1 : alarmas.map((a) => a.id).reduce((a, b) => a > b ? a : b) + 1);

    return (alarmas: alarmas, nextId: nextId);
  }
}
