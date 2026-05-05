/// Modelo que representa una alarma del despertador.
///
/// Contiene todos los datos necesarios para programar, mostrar y persistir
/// una alarma: hora de disparo, etiqueta, días de repetición y estado.
class Alarma {
  /// Identificador único de la alarma.
  final int id;

  /// Fecha y hora exacta del próximo disparo.
  DateTime hora;

  /// Texto descriptivo que muestra el usuario (ej: "Despertar a María").
  String etiqueta;

  /// Indica si la alarma está activada o desactivada.
  bool activa;

  /// Indica si la alarma fue pospuesta (snooze) y está esperando.
  bool pospuesta;

  /// Días de la semana en que se repite (1=Lunes, 7=Domingo).
  /// Lista vacía = alarma de una sola vez.
  List<int> diasSemana;

  Alarma({
    required this.id,
    required this.hora,
    required this.etiqueta,
    this.activa = true,
    this.pospuesta = false,
    List<int>? diasSemana,
  }) : diasSemana = diasSemana ?? [];

  /// Convierte la alarma a un mapa JSON para persistencia.
  Map<String, dynamic> toJson() => {
    'id': id,
    'hora': hora.toIso8601String(),
    'etiqueta': etiqueta,
    'activa': activa,
    'pospuesta': pospuesta,
    'diasSemana': diasSemana,
  };

  /// Crea una instancia de Alarma desde un mapa JSON.
  factory Alarma.fromJson(Map<String, dynamic> json) {
    final alarma = Alarma(
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

  /// Crea una copia de la alarma con los campos modificados.
  Alarma copyWith({
    int? id,
    DateTime? hora,
    String? etiqueta,
    bool? activa,
    bool? pospuesta,
    List<int>? diasSemana,
  }) {
    return Alarma(
      id: id ?? this.id,
      hora: hora ?? this.hora,
      etiqueta: etiqueta ?? this.etiqueta,
      activa: activa ?? this.activa,
      pospuesta: pospuesta ?? this.pospuesta,
      diasSemana: diasSemana ?? List<int>.from(this.diasSemana),
    );
  }

  @override
  String toString() => 'Alarma(id: $id, hora: $hora, etiqueta: $etiqueta, activa: $activa)';
}
