# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Flutter alarm clock app ("Mi Despertador") written in Spanish. Targets Android/iOS/Linux/macOS/Windows/Web.
Theme seed color: `Color(0xFF1565C0)` (blue). Material 3, no dark mode.

## Commands

```bash
flutter run                          # run on connected device
flutter run -d <device-id>          # run on specific device
flutter devices                      # list available devices
flutter build apk                    # Android release APK
flutter build ios                    # iOS
flutter build linux                  # Linux desktop
flutter test                         # all tests
flutter test test/widget_test.dart   # single file
flutter analyze                      # lint — must pass with ZERO issues
flutter pub get                      # install dependencies
flutter pub upgrade                  # upgrade dependencies
```

## Architecture (MVP)

```
lib/
  main.dart                          # Entry point. Calls AudioService.prepararSonido(), then runApp().
  models/
    alarma.dart                      # Mutable data model. toJson/fromJson/copyWith.
  services/
    audio_service.dart               # Generates WAV sweep file once on startup.
    storage_service.dart             # SharedPreferences persistence (alarm list + nextId).
    alarm_service.dart               # Wraps `alarm` package: set/stop/ringingStream.
    permission_service.dart          # Android exact-alarm permission + Do Not Disturb check.
  presenters/
    alarmas_presenter.dart           # ALL business logic. View implements AlarmasView.
  screens/
    pantalla_alarmas.dart            # Main screen (View). Implements AlarmasView.
    pantalla_alarma_activa.dart      # Fullscreen ringing UI. Slide-to-dismiss + countdown.
  widgets/
    dialogo_alarma.dart              # Modal for creating/editing alarms. Two-step flow.
    tarjeta_alarma.dart              # Alarm list card. Dismissible (swipe-left to delete).
    slide_desbloqueo.dart            # Random-direction slide-to-unlock widget.
  utils/
    constantes.dart                  # archivoSonido, nombresDias, claveAlarmas, claveNextId.
    date_utils.dart                  # proximaFecha, textoTiempoRestante, formatearHoraAMPM, etc.
```

**MVP data flow:**
```
User action
  → View (PantallaAlarmas)
    → Presenter method (e.g. agregarAlarma)
      → Services (AlarmService, StorageService)
      → Model mutation
      → AlarmasView callback (e.g. onAlarmaAgregada)
        → View setState()
```

## Data Model — `Alarma`

| Field | Type | Description |
|---|---|---|
| `id` | `int` (final) | Unique ID. Auto-incremented via `_nextId` in presenter. |
| `hora` | `DateTime` | **Next scheduled fire time.** Changes on snooze (set to now+5min). |
| `horaDelDia` | `int` | **User-configured hour (0–23). Never changes on snooze.** Use this for display and rescheduling. |
| `minutoDelDia` | `int` | **User-configured minute (0–59). Never changes on snooze.** |
| `etiqueta` | `String` | Display label. Defaults to `'Alarma'` if blank. |
| `activa` | `bool` | Whether the alarm is enabled. |
| `pospuesta` | `bool` | True while waiting for a snooze to fire. |
| `diasSemana` | `List<int>` | Repeat days (1=Mon…7=Sun). Empty = one-shot. |

**Critical distinction:** `hora.hour`/`hora.minute` may differ from `horaDelDia`/`minutoDelDia`
when the alarm is snoozed. Always use `horaDelDia`/`minutoDelDia` for:
- Displaying the alarm time (cards, editor)
- Rescheduling after dismiss (`detenerAlarma`, `_cargarAlarmas`)
- Recalculating next date (`actualizarHora`, `actualizarAlarmaCompleta`)

`hora.toIso8601String()` is persisted. `horaDelDia`/`minutoDelDia` are also persisted.
Old records without these fields fall back to `hora.hour`/`hora.minute` on load.

## Presenter — `AlarmasPresenter`

### AlarmasView interface (View must implement all methods)

| Method | When called |
|---|---|
| `onAlarmasCargadas()` | Initial load + every 1-second timer tick (clock update). |
| `onAlarmaAgregada()` | After adding or restoring (undo) an alarm. |
| `onAlarmaActualizada()` | After toggle, edit, snooze, or dismiss. |
| `onAlarmaEliminada()` | After deleting an alarm. |
| `onPermisoNecesario(bool)` | When exact-alarm permission check completes. |
| `onModoNoMolestarCambiado(bool)` | When DND state changes (checked on resume). |
| `onMostrarPantallaAlarma(Alarma)` | Push fullscreen ringing route. |
| `onAlarmaSonandoEnForeground(Alarma)` | Show in-app banner (app is in foreground). |
| `getContext()` | Returns the View's BuildContext (for dialog navigation). |

### Key internal state

| Field | Purpose |
|---|---|
| `_alarmas` | Live list. Exposed as `List.unmodifiable` via `alarmas` getter. |
| `_nextId` | Auto-increment counter persisted alongside alarms. |
| `_ahora` | `DateTime.now()` updated every second by `_timer`. |
| `_alarmaSonando` | The alarm currently ringing (null otherwise). Cleared on dismiss/snooze. |
| `_alertaEnPantalla` | Guards against stacking multiple ringing routes on `onAppResumed`. |
| `_prevAlarmSet` | Previous `AlarmSet` snapshot; used to detect new alarms in the ringing stream. |

### Alarm lifecycle

```
agregarAlarma(hora, minuto, etiqueta, dias)
  → proximaFecha(hora, minuto, dias)     # compute next DateTime
  → AlarmService.programar(alarma)
  → StorageService.guardarAlarmas()
  → onAlarmaAgregada()

toggleAlarma(alarma, activa=true)
  → AlarmService.programar(alarma)       # or .detener() if activa=false
  → guardarAlarmas → onAlarmaActualizada

[alarm fires] → Alarm.ringing stream
  → _onAlarmaSonando(AlarmSet)
      lifecycle == resumed?
        yes → onAlarmaSonandoEnForeground  # in-app banner
        no  → onMostrarPantallaAlarma      # push fullscreen route
      _alertaEnPantalla = true

posponerAlarma(alarma)
  → alarma.hora = now + 5min             # hora changes, horaDelDia/minutoDelDia DO NOT
  → alarma.pospuesta = true
  → AlarmService.programar(alarma)       # schedules snooze
  → _alarmaSonando = null, _alertaEnPantalla = false

detenerAlarma(alarma)
  → AlarmService.detener(alarma.id)
  → alarma.pospuesta = false
  → if diasSemana.isNotEmpty:
      alarma.hora = proximaFecha(horaDelDia, minutoDelDia, diasSemana)
      AlarmService.programar(alarma)     # reschedule for next occurrence
  → _alarmaSonando = null, _alertaEnPantalla = false

_cargarAlarmas() [on app start]
  → for each active alarm with hora.isBefore(now):
      alarma.hora = proximaFecha(horaDelDia, minutoDelDia, diasSemana)
      alarma.pospuesta = false           # expired snooze is discarded
  → re-programs all active future alarms

onAppResumed()
  → _verificarModoNoMolestar()
  → if _alarmaSonando != null && !_alertaEnPantalla:
      show ringing screen (prevents duplicate routes)
```

### `proximaFecha(hora, minuto, diasSemana)` behavior
- `diasSemana` empty → next occurrence of that time (today if future, tomorrow if past)
- `diasSemana` non-empty → scans next 7 days for the first matching weekday after now
- Fallback (all 7 days checked and none qualify) → adds 7 days to today's date

## Screens

### `PantallaAlarmas` (main screen)

- Implements `AlarmasView` and `WidgetsBindingObserver`
- `initState`: creates presenter, calls `presenter.iniciar()`, checks for empty list to animate FAB
- `didChangeAppLifecycleState`: calls `presenter.onAppResumed()` on `AppLifecycleState.resumed`
- Contains `_BannerAlarmaSonando` — shown when alarm fires in foreground (not fullscreen)
- FAB animates with pulse when alarm list is empty (`_FABAnimado` widget)
- Swipe-to-delete shows undo `SnackBar` for 4 seconds (`_eliminarConUndo`)

### `PantallaAlarmaActiva` (ringing screen)

- `PopScope(canPop: false)` — back button disabled
- Enters `SystemUiMode.immersiveSticky`; restores `edgeToEdge` on dispose
- Shows real-time clock (updates every second) with pulsing `AnimationController`
- Slide-to-dismiss: `SlideDesbloqueo` with `umbral: 0.75`
  - On success → `_iniciarCountdown()` (5-second countdown, then auto-calls `detener`)
- Fallback buttons ("Posponer 5 min" / "Detener") appear after 10 seconds
  - Hidden once `_desbloqueado = true` (countdown running)
- `_CountdownWidget`: shows remaining seconds inside a `CircularProgressIndicator`

## Widgets

### `DialogoAlarma`
Two-step modal:
1. **Simple mode** (default): large time selector + "Listo" button → saves with empty `diasSemana`
2. **Config mode** (tap "Configurar"): adds name field + repeat days selector
   - Quick-select chips: "Lun–Vie", "Todos", "Fin de semana"
   - Individual day chips (Lun–Dom), sorted on selection
   - Uses `horaDelDia`/`minutoDelDia` (not `hora`) when pre-filling for edit
- Time picker: native `showTimePicker`, styled with `RoundedRectangleBorder`

### `TarjetaAlarma`
- `Dismissible` (swipe left) → calls `onEliminar`
- Displays `horaDelDia`/`minutoDelDia` (not `hora.hour/minute`) — correct even during snooze
- Orange dot badge on the icon when `alarma.pospuesta == true`
- "HOY" badge shown when `alarma.hora` falls on today
- Opacity 0.65 + grey card when alarm is disabled

### `SlideDesbloqueo`
- Picks random direction at init (`direccionAleatoria()` returns one of 4 unit vectors)
- Uses dot product to measure progress along the target direction
- If dragged in wrong direction (distance > 20px), changes to a new random direction
- Progress bar: white → orange → green as user drags
- Calls `onDesbloqueado()` when progress ≥ `umbral` (default 0.75)

## Services

### `AlarmService`
- Wraps the `alarm` ^5.2.1 package
- `programar(alarma)` → `Alarm.set(AlarmSettings)`: uses `alarma.hora` for dateTime
- `detener(id)` → `Alarm.stop(id)`
- `ringingStream` → `Alarm.ringing` (a `Stream<AlarmSet>`)
- Audio: `loopAudio: true`, `volume: 1.0`, `volumeEnforced: true`, `vibrate: true`
- Notification body: `"${alarma.etiqueta} — ${formatearHoraAMPM(alarma.hora)}"`

### `AudioService`
- Generates `alarma_limpieza.wav` in `getApplicationDocumentsDirectory()` if not present
- Format: PCM mono 16-bit 44100 Hz, 3 seconds, frequency sweep 200 Hz → 1000 Hz
- File is generated once and reused; `main()` calls `prepararSonido()` before `runApp()`

### `StorageService`
- `guardarAlarmas(List<Alarma>, nextId)` → `SharedPreferences.setStringList('alarmas', ...)`
- `cargarAlarmas()` → returns `({List<Alarma> alarmas, int nextId})`
- `nextId` fallback: `max(all ids) + 1` if key missing (migration safety)

### `PermissionService`
- `verificarPermisoAlarmasExactas()` → `Permission.scheduleExactAlarm.isGranted` (Android only; returns `true` on other platforms)
- `verificarModoNoMolestar()` → `DoNotDisturbPlugin().isDndEnabled()` (Android only; returns `false` elsewhere)
- `abrirConfiguracion()` → `openAppSettings()`

## Key dependencies

| Package | Version | Purpose |
|---|---|---|
| `alarm` | ^5.2.1 | Native alarm scheduling. No built-in UI. |
| `permission_handler` | ^11.0.0 | `SCHEDULE_EXACT_ALARM` on Android 12+. |
| `shared_preferences` | ^2.2.0 | Alarm list persistence. |
| `do_not_disturb` | ^1.0.3 | DND status check on Android. |
| `path_provider` | ^2.1.0 | Documents directory for WAV file. |

## Critical gotchas

- **`alarm` package has no UI.** `Alarm.ringing` is a `Stream<AlarmSet>`. You must listen and push your own route. Done in `AlarmasPresenter._iniciarEscuchaRinging()`.

- **`AlarmSet` import.** Must be `import 'package:alarm/utils/alarm_set.dart'` — not re-exported from the main package.

- **Audio before `Alarm.init()`.** `main()` calls `AudioService().prepararSonido()` before `runApp()`, which calls `Alarm.init()` inside `presenter.iniciar()`. Order matters.

- **`horaDelDia`/`minutoDelDia` are canonical.** `alarma.hora` can be the snooze time. Any code that displays the user-set time or reschedules must use `horaDelDia`/`minutoDelDia`. Affected sites: `TarjetaAlarma`, `DialogoAlarma.initState`, all rescheduling in presenter.

- **`_alertaEnPantalla` flag.** Prevents `onAppResumed` from pushing duplicate ringing routes when the user minimizes and restores the app while an alarm rings. Reset in `detenerAlarma` and `posponerAlarma`.

- **`PopScope(canPop: false)`.** `pantalla_alarma_activa.dart` blocks back navigation during ringing. Uses `PopScope` (not deprecated `WillPopScope`).

- **Stale test.** `test/widget_test.dart` asserts on old UI text. Current empty-state text is `'No tienes alarmas'` + `'Toca + para crear tu primera alarma'`. Update before running `flutter test`.

- **`_cargarAlarmas` resets snooze.** If the app is killed while an alarm is snoozed and the snooze time has already passed on restart, the alarm is silently rescheduled to the next normal occurrence (`pospuesta = false`). This is intentional: expired snoozes are not re-triggered.

- **One-shot alarms are not reprogrammed after dismiss.** `detenerAlarma` only reprograms if `diasSemana.isNotEmpty`. One-shot alarms stay in the list with a past `hora` until the user deletes or re-enables them.

- **No concurrency guard on `iniciar()`.** Calling `iniciar()` twice would create two timers and two stream subscriptions. It is only called once from `PantallaAlarmas.initState()` and must remain so.

## Conventions

- All variable names, comments, and UI strings are in **Spanish**.
- Day numbering follows `DateTime.weekday`: 1=Monday (`Lun`) … 7=Sunday (`Dom`).
- `nombresDias` index 0 = Monday (index = weekday - 1).
- `flutter_lints` default rules — no custom overrides in `analysis_options.yaml`.
- `flutter analyze` must pass with **zero issues** before committing.
- Alarm IDs are positive integers starting at 1. The `alarm` package requires `id > 0`.
