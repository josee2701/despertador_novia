# Bella Durmiente (Mi Despertador)

App de alarmas para Android que **te obliga a demostrar que estás despierto**.

La diferencia con cualquier otro despertador: apagar la alarma no la apaga. Deslizas, la
alarma calla — y **vuelve a sonar a los 30 segundos**. Solo el segundo deslizamiento la
apaga de verdad. Se acabó el "lo apago medio dormido y me vuelvo a dormir".

Publicada en Google Play · Versión `1.3.2+7` · `com.soy.josec.bella_durmiente`

---

## Características principales

### 🔁 Confirmación de despertar (la función central)

Cuando apagas una alarma deslizando:

1. Aparece un countdown de 5 segundos. La alarma **sigue sonando** durante esos segundos:
   última oportunidad de cambiar de opinión.
2. La pantalla se cierra y el sonido para.
3. **A los 30 segundos la alarma vuelve a sonar.**
4. Tienes que deslizar otra vez para confirmar que estás despierto.
5. Solo entonces queda apagada definitivamente.

Detalles:
- Posponer (snooze) **no** activa la confirmación.
- En alarmas recurrentes, tras confirmar se reprograma sola la siguiente ocurrencia.
- Si la app se reinicia o la alarma se para desde fuera, la confirmación pendiente se
  limpia sola: nunca se queda atrapada.

### ⏰ Recordatorio antes de que suene

Una notificación **silenciosa** avisa 30 minutos antes de que la alarma dispare, con el
nombre y la hora. Sirve para desactivarla con antelación si ese día no la necesitas.

Es silenciosa a propósito (sin sonido ni vibración): dispara de madrugada y no debe
despertar a nadie.

> **Próximamente:** pasará a avisar **1 hora antes** y llevará botones de
> **Cancelar alarma / Mantener** directamente en la notificación, sin abrir la app.

### 📱 Crear y gestionar alarmas

- **Flujo rápido:** `+` → elige la hora → "Listo". Sin configuración obligatoria.
- **Flujo completo:** "Repetición y nombre" añade etiqueta y días, con atajos
  (Lun–Vie / Todos / Fin de semana).
- **Una sola vez:** sin días seleccionados; suena una vez y se desactiva sola.
- **Recurrentes:** elige los días; la app calcula la próxima fecha automáticamente.
- **Editar:** toca cualquier tarjeta.
- **Eliminar con deshacer:** desliza a la izquierda; el SnackBar de "Deshacer" dura 4 s.
- **Activar/desactivar:** interruptor por tarjeta. Al reactivar, la hora se recalcula a
  futuro.

### 🔔 Pantalla cuando la alarma suena

- **Pantalla completa bloqueante**, gradiente oscuro y reloj en tiempo real.
- **Deslizar para apagar en dirección aleatoria** (← → ↑ ↓), distinta en cada disparo. Si
  deslizas en la dirección equivocada, la dirección cambia.
  Los cuatro ejes exigen el mismo recorrido: no se apaga de un roce.
- **Countdown de 5 segundos** tras deslizar correctamente.
- **Botón de emergencia** ("Posponer 5 min") a los 10 segundos, por si el deslizador falla.
- **Botón físico de retroceso desactivado** mientras suena.

### 😴 Posponer (snooze)

- Pospone **5 minutos** exactos desde que se pulsa.
- La hora original nunca cambia: la tarjeta siempre muestra la hora configurada, no la
  del snooze.
- La notificación del sistema muestra "Pospuesta (HH:MM)" con la hora real de re-disparo.
- Las alarmas pospuestas llevan un **punto naranja** en el icono.

### 🏠 Pantalla principal

- **Header** con "Próxima alarma: [nombre] en [tiempo]".
- **Orden:** activas primero, luego por hora configurada; las desactivadas al final.
- **FAB animado** con pulso cuando la lista está vacía.
- **Badge "HOY"** en las alarmas activas que disparan hoy.
- **Icono según el horario:** sol (mañana), sol tenue (tarde), luna (noche).
- **Cuatro avisos** cuando algo puede impedir que la alarma suene: Modo No Molestar,
  permiso de alarmas exactas, permiso de pantalla completa e Inicio automático del
  fabricante.

### 🩺 Diagnóstico integrado

Un icono en la barra superior abre la pantalla de Diagnóstico:

- Estado de cada permiso crítico, **con botón para arreglarlo** en el acto.
- Guía paso a paso para fabricantes que matan apps (Xiaomi/MIUI, Huawei, Oppo…).
- **Registro persistente de eventos** con marca de tiempo: cuándo se programó cada alarma,
  cuándo disparó, cuántos segundos sonó, y cualquier error o crash de la app.
- Botón para **compartir el reporte completo** (dispositivo + permisos + log) por WhatsApp
  o email.

Si el log dice "programada" pero nunca "DISPARÓ", el sistema mató la app: eso es
exactamente lo que esta pantalla existe para demostrar.

### 🛡️ Fiabilidad en teléfonos hostiles

Android —y MIUI en particular— mata procesos en segundo plano de forma agresiva. La app
se defiende en varios frentes:

- El sonido **no se corta** al quitar la app de "Recientes".
- La alarma se muestra **sobre la pantalla bloqueada** (full-screen intent).
- Un **receptor de arranque propio** reprograma las alarmas tras un reinicio rápido o una
  actualización, incluso cuando el sistema no entrega `BOOT_COMPLETED`.
- **Detección de reinicio** comparando el uptime entre sesiones.
- **Auditoría de alarmas** al abrir la app y al volver a primer plano: compara lo que
  debería estar programado con lo que el sistema tiene, cancela restos y repone lo que
  falta.
- Solicitud de **exención de optimización de batería**.
- Aviso si el sistema mata la app.

### 💰 Publicidad

La app se financia con Google AdMob:

- **Banner** fijo al pie de la pantalla principal (con reintento automático si la red
  falla).
- **Anuncio de apertura** al volver a la app, como máximo uno cada 4 horas.

Con una regla que no se negocia: **la publicidad nunca aparece mientras una alarma está
sonando**, ni en la pantalla de alarma activa, ni dentro de los diálogos, ni al abrir la
app por una alarma.

### 🔐 Permisos y compatibilidad

- **Android 12+:** `SCHEDULE_EXACT_ALARM` para alarmas exactas.
- **Android 13+:** `POST_NOTIFICATIONS`.
- **Android 14+:** permiso de pantalla completa (`USE_FULL_SCREEN_INTENT`), causa nº 1 de
  que la alarma no aparezca con el teléfono bloqueado.
- **Modo No Molestar:** se detecta y se avisa.
- Multiplataforma a nivel de compilación (Android / iOS / Linux / macOS / Windows / Web),
  pero Android es la plataforma real; el resto degrada a valores seguros.

---

## Arquitectura (MVP)

```
lib/
  main.dart                            # Captura global de errores, init de anuncios,
                                       # genera el WAV y arranca la app
  models/
    alarma.dart                        # Modelo mutable con toJson/fromJson/copyWith
  services/
    alarm_service.dart                 # Wrapper del package alarm (set/stop/isRinging)
    audio_service.dart                 # Genera el WAV de la alarma una sola vez
    storage_service.dart               # Persistencia con SharedPreferences
    permission_service.dart            # Permisos Android + canal nativo
    recordatorio_service.dart          # Política del aviso previo
    planificador_notificaciones.dart   # Notificaciones locales + zona horaria
    app_open_ad_manager.dart           # Anuncio de apertura y sus candados
    log_service.dart                   # Registro persistente de diagnóstico
  presenters/
    alarmas_presenter.dart             # Toda la lógica de negocio (MVP Presenter)
  screens/
    pantalla_alarmas.dart              # Pantalla principal (MVP View)
    pantalla_alarma_activa.dart        # Pantalla completa mientras suena
    pantalla_diagnostico.dart          # Permisos, guía OEM, log y reporte
  widgets/
    dialogo_alarma.dart                # Modal de crear/editar (flujo en dos pasos)
    tarjeta_alarma.dart                # Tarjeta de la lista, deslizable
    slide_desbloqueo.dart              # Deslizador de dirección aleatoria
    banner_ad_widget.dart              # Banner de AdMob con reintento
  utils/
    constantes.dart                    # Claves de storage, días, ID de anuncio
    date_utils.dart                    # Fechas, formato AM/PM, direcciones
```

**Flujo de datos MVP:**

```
Acción del usuario
  → View (PantallaAlarmas)
    → Método del Presenter (p. ej. agregarAlarma)
      → Servicios (AlarmService, RecordatorioService, StorageService)
      → Mutación del modelo
      → Callback de AlarmasView (p. ej. onAlarmaAgregada)
        → setState en la View
```

---

## Modelo de datos — `Alarma`

| Campo | Tipo | Descripción |
|---|---|---|
| `id` | `int` | ID único, autoincremental. Siempre > 0. |
| `hora` | `DateTime` | **Próximo disparo.** Cambia al posponer y durante la confirmación. |
| `horaDelDia` | `int` | **Hora configurada (0–23). No cambia nunca.** |
| `minutoDelDia` | `int` | **Minuto configurado (0–59). No cambia nunca.** |
| `etiqueta` | `String` | Nombre visible. "Alarma" si se deja en blanco. |
| `activa` | `bool` | Si la alarma está habilitada. |
| `pospuesta` | `bool` | True mientras espera el snooze de 5 min. |
| `confirmacionPendiente` | `bool` | True mientras espera la confirmación de los 30 s. |
| `diasSemana` | `List<int>` | Días de repetición (1=Lun…7=Dom). Vacío = una sola vez. |

> **Regla crítica:** `hora` puede ser la hora configurada, la del snooze **o** la de la
> confirmación. Para mostrar al usuario y para reprogramar, usa siempre
> `horaDelDia`/`minutoDelDia`.

---

## Ciclo de vida de una alarma

```
agregarAlarma(hora, minuto, etiqueta, dias)
  → proximaFecha → programar alarma + recordatorio → guardar → onAlarmaAgregada

[la alarma suena] → Alarm.ringing
  ¿ya sonaba al arrancar? → pantalla completa (la app se abrió POR la alarma)
  ¿app visible?           → banner dentro de la app
  ¿app en segundo plano?  → lo resuelve onAppResumed al volver

[el usuario desliza]
  → countdown de 5 s
  → ¿confirmacionPendiente == false?
       SÍ → cerrarConConfirmacion → calla y reprograma para dentro de 30 s
       NO → detenerAlarma → apagado definitivo

detenerAlarma
  → detener alarma + cancelar recordatorio
  → recurrente → proximaFecha → reprogramar alarma + recordatorio
  → una sola vez → activa = false

posponerAlarma
  → detener → hora = ahora + 5 min → reprogramar (no activa la confirmación)

[la app arranca] → cargar alarmas
  → respetar intactas las alarmas que estén sonando ahora mismo
  → auditar lo programado en el sistema (cancelar restos, reponer lo perdido)
  → normalizar vencidas: una vez → desactivar; recurrente → recalcular
  → reprogramar las activas futuras
```

---

## Dependencias principales

| Paquete | Versión | Uso |
|---|---|---|
| `alarm` | ^5.2.1 | Alarmas nativas en Android/iOS |
| `google_mobile_ads` | ^5.1.0 | Banner y anuncio de apertura |
| `flutter_local_notifications` | ^22.3.0 | Recordatorio previo |
| `timezone` / `flutter_timezone` | ^0.11.1 / ^5.1.0 | Zona horaria real para programar |
| `permission_handler` | ^11.0.0 | Alarmas exactas, notificaciones, batería |
| `shared_preferences` | ^2.2.0 | Persistencia de alarmas |
| `do_not_disturb` | ^1.0.3 | Detección del modo No Molestar |
| `path_provider` | ^2.1.0 | Directorio de documentos (WAV y log) |
| `share_plus` | ^13.1.0 | Compartir el reporte de diagnóstico |
| `device_info_plus` | ^13.1.0 | Fabricante y modelo del dispositivo |
| `package_info_plus` | ^10.1.0 | Versión de la app en el reporte |

---

## Comandos de desarrollo

```bash
flutter run                 # ejecutar en el dispositivo conectado
flutter run -d <device-id>  # ejecutar en un dispositivo concreto
flutter devices             # listar dispositivos
flutter build apk           # APK de release
flutter build appbundle     # AAB para Play Store
flutter analyze             # lint — debe pasar con 0 issues antes de commitear
flutter test                # suite completa
flutter pub get             # instalar dependencias
```

---

## Tests

**177 tests**, todos en verde. La suite corre entera sin plugins nativos: los SDK quedan
detrás de interfaces y se sustituyen por fakes.

```
test/unit/
  presenter_test.dart                        ← lógica del presenter completa
  storage_test.dart                          ← persistencia y migración
  date_utils_test.dart                       ← fechas, formato y direcciones
  alarma_test.dart                           ← modelo, JSON y copyWith
  recordatorio_service_test.dart             ← cuándo se avisa y cuándo se omite
  planificador_local_notifications_test.dart ← inicialización perezosa
  app_open_ad_manager_test.dart              ← candados del anuncio de apertura
  log_service_test.dart                      ← recorte por lotes y cola de E/S
  dobles_notificaciones.dart                 ← dobles compartidos
test/widget/
  pantalla_alarma_activa_test.dart
  slide_desbloqueo_test.dart
  tarjeta_alarma_test.dart
integration_test/
  app_test.dart
```

---

## Notas técnicas importantes

- **`alarm` no trae UI.** `Alarm.ringing` emite un `AlarmSet`; la app escucha y hace push
  de su propia ruta.
- **`AlarmSet` necesita su propio import:** `package:alarm/utils/alarm_set.dart`.
- **El audio se genera antes de `Alarm.init()`:** `main()` espera a
  `AudioService().prepararSonido()` antes de `runApp()`.
- **El recordatorio nunca se programa como alarma nativa.** Hacerlo dejaba vivo el
  foreground service y hacía que la alarma real se descartara. Es una notificación local.
- **`PopScope(canPop: false)`** bloquea el botón de retroceso mientras suena.
- **Los snoozes vencidos se descartan** al reiniciar: se reprograma la próxima ocurrencia
  normal.
- **Dos alarmas a la misma hora no funcionan:** el sistema descarta la segunda. Una
  "alarma de respaldo" a la misma hora no suena.

Para el detalle completo de arquitectura, decisiones y trampas conocidas, ver
[AGENTS.md](AGENTS.md).
