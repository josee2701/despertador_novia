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

/// Canal de notificaciones del aviso "tu alarma suena en 30 minutos".
/// Silencioso a propósito: dispara de madrugada y no debe despertar a nadie.
const canalRecordatorios = 'recordatorios';

/// Marca que el usuario ya pasó por la pantalla de "Inicio automático" del
/// fabricante. No hay forma de consultar el estado real del ajuste, así que se
/// guarda que el aviso fue atendido para no repetirlo.
const claveAutostartAtendido = 'autostartAtendido';

/// ID del bloque App Open de AdMob para Android en producción.
///
/// Vacío = el anuncio de apertura queda desactivado (comportamiento seguro).
/// Rellenar con el ID real creado en la consola de AdMob.
const idAppOpenAdAndroid = '';
