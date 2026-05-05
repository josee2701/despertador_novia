import 'dart:math';

import 'package:flutter/material.dart';

/// Calcula la próxima fecha de disparo para una alarma.
///
/// [hora] y [minuto] definen la hora del día.
/// [diasSemana] usa la convención DateTime.weekday (1=Lunes, 7=Domingo).
/// Si [diasSemana] está vacío, devuelve el próximo instante a esa hora
/// (mañana si ya pasó hoy).
DateTime proximaFecha(int hora, int minuto, List<int> diasSemana) {
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

  return base.add(const Duration(days: 7));
}

/// Formatea una hora en formato 12h sin ceros a la izquierda en la hora.
/// Ejemplo: 14:05 → "2:05"
String formatearHora(DateTime dt) {
  final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// Devuelve 'AM' o 'PM' según la hora.
String periodo(DateTime dt) => dt.hour < 12 ? 'AM' : 'PM';

/// Devuelve la hora actual formateada como HH:MM:SS.
String horaActualHHMMSS(DateTime ahora) {
  final h = ahora.hour.toString().padLeft(2, '0');
  final m = ahora.minute.toString().padLeft(2, '0');
  final s = ahora.second.toString().padLeft(2, '0');
  return '$h:$m:$s';
}

/// Calcula el texto descriptivo del tiempo restante hasta [alarma].
///
/// Devuelve un string del tipo "en 2h 15min" o "en 30min".
/// Si la alarma ya pasó o no es válida, devuelve null.
String? textoTiempoRestante(DateTime alarma, DateTime ahora) {
  if (!alarma.isAfter(ahora)) return null;

  final diff = alarma.difference(ahora);
  final horas = diff.inHours;
  final minutos = diff.inMinutes.remainder(60);

  return horas > 0 ? '${horas}h ${minutos}min' : '${minutos}min';
}

/// Selecciona una dirección aleatoria para el widget de deslizamiento.
/// Retorna un vector Offset normalizado:
/// - Derecha: (1, 0)
/// - Izquierda: (-1, 0)
/// - Abajo: (0, 1)
/// - Arriba: (0, -1)
Offset direccionAleatoria() {
  final rng = Random();
  return switch (rng.nextInt(4)) {
    0 => const Offset(1, 0),
    1 => const Offset(-1, 0),
    2 => const Offset(0, 1),
    _ => const Offset(0, -1),
  };
}

/// Devuelve el ícono de flecha correspondiente a la dirección del vector.
IconData iconoDireccion(Offset direccion) {
  if (direccion.dx == 1) return Icons.arrow_forward;
  if (direccion.dx == -1) return Icons.arrow_back;
  if (direccion.dy == 1) return Icons.arrow_downward;
  return Icons.arrow_upward;
}

/// Texto descriptivo de la dirección para instrucciones al usuario.
String textoDireccion(Offset direccion) {
  if (direccion.dx == 1) return 'desliza a la derecha';
  if (direccion.dx == -1) return 'desliza a la izquierda';
  if (direccion.dy == 1) return 'desliza hacia abajo';
  return 'desliza hacia arriba';
}
