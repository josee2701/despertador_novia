/// Modelo que representa una alarma del despertador.
///
/// Contiene todos los datos necesarios para programar, mostrar y persistir
/// una alarma: hora de disparo, etiqueta, días de repetición y estado.
class Alarma {
  /// Identificador único de la alarma.
  final int id;

  /// Fecha y hora exacta del próximo disparo (puede ser hora de snooze).
  DateTime hora;

  /// Hora del día configurada por el usuario. No cambia al posponer.
  int horaDelDia;

  /// Minuto configurado por el usuario. No cambia al posponer.
  int minutoDelDia;

  /// Texto descriptivo que muestra el usuario (ej: "Despertar a María").
  String etiqueta;

  /// Indica si la alarma está activada o desactivada.
  bool activa;

  /// Indica si la alarma fue pospuesta (snooze) y está esperando.
  bool pospuesta;

  /// Indica si la alarma está pendiente de confirmación (cerró pero sonará a los 30s).
  bool confirmacionPendiente;

  /// Días de la semana en que se repite (1=Lunes, 7=Domingo).
  /// Lista vacía = alarma de una sola vez.
  List<int> diasSemana;

  Alarma({
    required this.id,
    required this.hora,
    required this.etiqueta,
    this.activa = true,
    this.pospuesta = false,
    this.confirmacionPendiente = false,
    List<int>? diasSemana,
    int? horaDelDia,
    int? minutoDelDia,
  })  : diasSemana = diasSemana ?? [],
        horaDelDia = horaDelDia ?? hora.hour,
        minutoDelDia = minutoDelDia ?? hora.minute;

  /// Convierte la alarma a un mapa JSON para persistencia.
  Map<String, dynamic> toJson() => {
    'id': id,
    'hora': hora.toIso8601String(),
    'horaDelDia': horaDelDia,
    'minutoDelDia': minutoDelDia,
    'etiqueta': etiqueta,
    'activa': activa,
    'pospuesta': pospuesta,
    'confirmacionPendiente': confirmacionPendiente,
    'diasSemana': diasSemana,
  };

  /// Crea una instancia de Alarma desde un mapa JSON.
  factory Alarma.fromJson(Map<String, dynamic> json) {
    final hora = DateTime.parse(json['hora'] as String);
    final alarma = Alarma(
      id: json['id'] as int,
      hora: hora,
      etiqueta: json['etiqueta'] as String,
      diasSemana: (json['diasSemana'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          [],
      // Fallback a hora.hour/minute para datos guardados antes de este campo.
      horaDelDia: (json['horaDelDia'] as int?) ?? hora.hour,
      minutoDelDia: (json['minutoDelDia'] as int?) ?? hora.minute,
    );
    alarma.activa = json['activa'] as bool;
    alarma.pospuesta = (json['pospuesta'] as bool?) ?? false;
    alarma.confirmacionPendiente = (json['confirmacionPendiente'] as bool?) ?? false;
    return alarma;
  }

  /// Crea una copia de la alarma con los campos modificados.
  Alarma copyWith({
    int? id,
    DateTime? hora,
    String? etiqueta,
    bool? activa,
    bool? pospuesta,
    bool? confirmacionPendiente,
    List<int>? diasSemana,
    int? horaDelDia,
    int? minutoDelDia,
  }) {
    return Alarma(
      id: id ?? this.id,
      hora: hora ?? this.hora,
      etiqueta: etiqueta ?? this.etiqueta,
      activa: activa ?? this.activa,
      pospuesta: pospuesta ?? this.pospuesta,
      confirmacionPendiente: confirmacionPendiente ?? this.confirmacionPendiente,
      diasSemana: diasSemana ?? List<int>.from(this.diasSemana),
      horaDelDia: horaDelDia ?? this.horaDelDia,
      minutoDelDia: minutoDelDia ?? this.minutoDelDia,
    );
  }

  @override
  String toString() => 'Alarma(id: $id, hora: $hora, etiqueta: $etiqueta, activa: $activa)';
}
