/// Nombre del archivo de audio generado localmente para la alarma.
const archivoSonido = 'alarma_limpieza.wav';

/// Nombres cortos de los días de la semana.
/// Índice 0 = Lunes (1 en DateTime.weekday), índice 6 = Domingo (7).
const nombresDias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

/// Claves de almacenamiento para SharedPreferences.
const claveAlarmas = 'alarmas';
const claveNextId = 'nextId';

/// Uptime del dispositivo (ms desde el último arranque) guardado en la sesión
/// anterior. Si el uptime actual es MENOR, hubo un reinicio entre sesiones:
/// las alarmas pudieron perderse si el OEM no entregó BOOT_COMPLETED.
const claveUltimoUptime = 'ultimoUptimeMs';
