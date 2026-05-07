# Mi Despertador

Una aplicación de alarmas para Android con una experiencia de usuario cuidada y mecanismos inteligentes para garantizar que el usuario realmente se despierte.

---

## Características principales

### Crear y gestionar alarmas
- **Flujo rápido:** toca `+` → selecciona la hora → toca "Listo". Sin configuración obligatoria.
- **Flujo completo:** toca "Configurar" para agregar nombre, días de repetición y atajos rápidos (Lun–Vie / Todos / Fin de semana).
- **Alarmas de una sola vez:** sin días seleccionados; se dispara una vez y se desactiva sola.
- **Alarmas recurrentes:** elige los días de la semana. La app calcula automáticamente la próxima fecha de disparo.
- **Edición inline:** toca cualquier tarjeta de alarma para editar hora, nombre y días.
- **Eliminación con deshacer:** desliza a la izquierda para eliminar. Aparece un SnackBar con "Deshacer" durante 4 segundos.
- **Activar/desactivar:** interruptor en cada tarjeta. Al reactivar, la hora se recalcula para que sea futura.

### Pantalla cuando la alarma suena
- **Pantalla completa bloqueante** con gradiente oscuro y reloj en tiempo real (hora:minutos:segundos).
- **Deslizar para apagar:** dirección aleatoria en cada disparo (←  →  ↑  ↓). Si el usuario desliza en la dirección equivocada, la dirección cambia.
- **Countdown de 5 segundos** tras deslizar correctamente. La alarma sigue sonando durante esos 5 segundos (última oportunidad de cambiar de opinión).
- **Botones de emergencia** (Posponer / Detener) que aparecen después de 10 segundos por si el deslizador no funciona.
- **Botón físico de retroceso desactivado** durante el sonido (`PopScope(canPop: false)`).

### Sistema de confirmación de despertar
Cuando el usuario apaga una alarma deslizando:

1. La pantalla se cierra normalmente.
2. A los **30 segundos** la alarma vuelve a sonar.
3. El usuario debe volver a deslizar para confirmar que está despierto.
4. Solo entonces la alarma queda apagada definitivamente.

**Notas:**
- El posponer (snooze) **no activa** la confirmación.
- Para alarmas recurrentes, tras confirmar la app reprograma la siguiente ocurrencia automáticamente.
- El diálogo de creación/edición informa al usuario de este comportamiento.

### Posponer (snooze)
- Pospone la alarma **5 minutos** exactos desde el momento en que se toca el botón.
- La hora original (`horaDelDia`/`minutoDelDia`) nunca cambia — la tarjeta siempre muestra la hora configurada, no la del snooze.
- La notificación del sistema muestra "Pospuesta (HH:MM)" con la hora real de re-disparo.
- Las alarmas pospuestas muestran un **punto naranja** en el ícono de la tarjeta.

### Alarma sonando en primer plano
Si la app está abierta cuando la alarma dispara, en lugar de interrumpir con una pantalla completa aparece un **banner discreto** en la parte superior con botones de Ver / Posponer 5 min / Detener.

### Pantalla principal
- **Header azul** con el texto "Próxima alarma: [nombre] en [tiempo]" o "No hay alarmas programadas".
- **Ordenación inteligente:** alarmas activas primero, luego ordenadas por hora configurada. Las desactivadas aparecen al final.
- **FAB animado** con pulso sutil cuando la lista está vacía.
- **Advertencia de Modo No Molestar** con botón directo a configuración si está activo.
- **Ícono de horario** en cada tarjeta: sol (mañana), sol con nieve (tarde), luna (noche).
- **Badge "HOY"** en tarjetas cuyo próximo disparo es hoy.
- Las alarmas desactivadas se muestran con opacidad reducida y tarjeta gris.

### Permisos y compatibilidad
- **Android 12+:** solicita permiso `SCHEDULE_EXACT_ALARM` (alarmas exactas). Si se deniega permanentemente, abre directamente la configuración del sistema.
- **Android 13+:** solicita permiso `POST_NOTIFICATIONS` automáticamente al iniciar.
- **Modo No Molestar:** detecta si está activo y alerta al usuario.
- Multiplataforma: Android / iOS / Linux / macOS / Windows / Web (el permiso de alarmas exactas solo aplica en Android).

### Persistencia y fiabilidad
- Las alarmas se guardan en `SharedPreferences` como JSON.
- Al reiniciar la app: alarmas vencidas de una sola vez se desactivan; alarmas recurrentes vencidas se reprograman para la siguiente ocurrencia.
- **Limpieza de alarmas fantasma:** al arrancar se comparan los IDs activos en `SharedPreferences` con los del paquete nativo. Cualquier ID nativo sin entrada local se detiene automáticamente.
- Datos corruptos en `SharedPreferences` son ignorados por entrada (no rompen la carga completa).

---

## Arquitectura (MVP)

```
lib/
  main.dart                          # Genera WAV y arranca la app
  models/
    alarma.dart                      # Modelo mutable con toJson/fromJson/copyWith
  services/
    audio_service.dart               # Genera el archivo WAV de audio una sola vez
    storage_service.dart             # Persistencia con SharedPreferences
    alarm_service.dart               # Wrapper del paquete alarm (set/stop/ringing)
    permission_service.dart          # Permisos Android (alarmas exactas, notificaciones, DND)
  presenters/
    alarmas_presenter.dart           # Toda la lógica de negocio (MVP Presenter)
  screens/
    pantalla_alarmas.dart            # Pantalla principal (MVP View)
    pantalla_alarma_activa.dart      # Pantalla fullscreen cuando suena la alarma
  widgets/
    dialogo_alarma.dart              # Modal de crear/editar alarma (flujo 2 pasos)
    tarjeta_alarma.dart              # Tarjeta de lista con Dismissible y estado visual
    slide_desbloqueo.dart            # Widget de deslizar en dirección aleatoria
  utils/
    constantes.dart                  # Rutas de audio, nombres de días, claves SharedPreferences
    date_utils.dart                  # Cálculo de fechas, formato AM/PM, tiempo restante
```

**Flujo de datos MVP:**
```
Acción del usuario
  → View (PantallaAlarmas)
    → Método del Presenter (ej: agregarAlarma)
      → Servicios (AlarmService, StorageService)
      → Mutación del modelo
      → Callback de AlarmasView (ej: onAlarmaAgregada)
        → setState en la View
```

---

## Modelo de datos — `Alarma`

| Campo | Tipo | Descripción |
|---|---|---|
| `id` | `int` | ID único. Auto-incrementado por el presenter. |
| `hora` | `DateTime` | **Próximo disparo.** Cambia al posponer o durante confirmación. |
| `horaDelDia` | `int` | **Hora configurada (0-23). No cambia nunca.** Usar para mostrar y reprogramar. |
| `minutoDelDia` | `int` | **Minuto configurado (0-59). No cambia nunca.** |
| `etiqueta` | `String` | Nombre visible. "Alarma" si se deja en blanco. |
| `activa` | `bool` | Si la alarma está habilitada. |
| `pospuesta` | `bool` | True mientras espera el snooze de 5 min. |
| `confirmacionPendiente` | `bool` | True cuando el usuario apagó pero aún debe confirmar a los 30s. |
| `diasSemana` | `List<int>` | Días de repetición (1=Lun…7=Dom). Vacío = una sola vez. |

> **Regla crítica:** `hora.hour`/`hora.minute` puede ser la hora del snooze o confirmación.
> Siempre usar `horaDelDia`/`minutoDelDia` para mostrar al usuario y para reprogramar.

---

## Ciclo de vida de una alarma

```
agregarAlarma(hora, minuto, etiqueta, dias)
  → proximaFecha(hora, minuto, dias)
  → AlarmService.programar → StorageService.guardar → onAlarmaAgregada

[Alarma suena] → Alarm.ringing stream
  → _onAlarmaSonando
      App en foreground → banner (onAlarmaSonandoEnForeground)
      App en background → onAppResumed maneja el fullscreen

[Usuario desliza en pantalla activa]
  → _iniciarCountdown (5 segundos)
  → ¿confirmacionPendiente == false?
      SÍ → cerrarConConfirmacion → audio para, programa en 30s
      NO → _detener → detenerAlarma → definitivamente apagada

detenerAlarma
  → AlarmService.detener
  → confirmacionPendiente = false
  → recurrente: proximaFecha → AlarmService.programar
  → una sola vez: activa = false

posponerAlarma
  → AlarmService.detener → hora = now+5min → AlarmService.programar

[App reinicia] → _cargarAlarmas
  → Limpiar IDs nativos huérfanos
  → Alarmas vencidas: una sola vez → desactivar; recurrente → reprogramar
  → Limpiar confirmacionPendiente en alarmas vencidas
```

---

## Dependencias principales

| Paquete | Versión | Uso |
|---|---|---|
| `alarm` | ^5.2.1 | Programación de alarmas nativas en Android/iOS |
| `permission_handler` | ^11.0.0 | `SCHEDULE_EXACT_ALARM` y `POST_NOTIFICATIONS` |
| `shared_preferences` | ^2.2.0 | Persistencia de alarmas |
| `do_not_disturb` | ^1.0.3 | Detección del modo No Molestar |
| `path_provider` | ^2.1.0 | Directorio de documentos para el WAV |

---

## Comandos de desarrollo

```bash
# Ejecutar en dispositivo conectado
flutter run

# Ejecutar en dispositivo específico
flutter run -d <device-id>

# Listar dispositivos disponibles
flutter devices

# Compilar APK para Android
flutter build apk

# Lint — debe pasar con 0 issues antes de hacer commit
flutter analyze

# Tests unitarios
flutter test

# Instalar dependencias
flutter pub get
```

---

## Tests

La suite de tests corre completamente sin plugins nativos usando fakes (`FakeAlarmService`, `FakeStorageService`, `FakePermissionService`).

```
test/unit/
  presenter_test.dart    ← lógica del presenter (agregarAlarma, toggleAlarma,
                            detenerAlarma, posponerAlarma, restaurarAlarma,
                            eliminarAlarma, onAppResumed, obtenerProximaAlarma,
                            cerrarConConfirmacion, confirmacionPendiente,
                            huérfanos nativos, dispose)
  storage_test.dart      ← persistencia (round-trip, datos corruptos, migración)
  date_utils_test.dart   ← utilidades de fecha (proximaFecha, formatearHoraAMPM,
                            textoTiempoRestante, iconos, direcciones)
```

```bash
flutter test             # corre todos los tests
```

---

## Notas técnicas importantes

- **`alarm` no tiene UI.** El stream `Alarm.ringing` emite `AlarmSet` — la app debe escucharlo y hacer push de su propia ruta.
- **`AlarmSet` necesita su propio import:** `package:alarm/utils/alarm_set.dart`.
- **El audio se genera antes de `Alarm.init()`.** `main()` llama `AudioService().prepararSonido()` antes de `runApp()`.
- **`_alertaEnPantalla`** evita apilar múltiples rutas si el usuario minimiza y restaura la app mientras suena.
- **`PopScope(canPop: false)`** bloquea el botón físico de retroceso en `PantallaAlarmaActiva`.
- **Snoozes expirados** al reiniciar la app se descartan silenciosamente (se reprograma la próxima ocurrencia normal).
- **`confirmacionPendiente`** se limpia automáticamente en `_cargarAlarmas`, `onAppResumed` y `_limpiarAlarmaSonandoExterna` para evitar que quede atrapado si la app se reinicia o la alarma se para externamente.
