# AGENTS.md

## Commands

```bash
flutter analyze       # lint + typecheck (must pass, 0 issues)
flutter test          # runs test/widget_test.dart (STALE — needs update)
flutter run           # run on connected device
flutter pub get       # install deps
```

**Order before committing:** `flutter analyze` → fix all issues → `flutter test` (after updating the stale test).

## Architecture (MVP)

```
lib/
  main.dart                          # Entry point (~30 lines). Initializes AudioService + runApp.
  models/alarma.dart                 # Data model with toJson/fromJson/copyWith.
  services/
    audio_service.dart               # Generates WAV sweep file in Documents dir.
    storage_service.dart             # SharedPreferences read/write for alarms.
    alarm_service.dart               # Wraps `alarm` package (set/stop/ringingStream).
    permission_service.dart           # Android exact-alarm + Do Not Disturb checks.
  presenters/alarmas_presenter.dart  # ALL business logic. View implements AlarmasView interface.
  screens/
    pantalla_alarmas.dart            # Main screen (View). Implements AlarmasView.
    pantalla_alarma_activa.dart      # Fullscreen alarm ringing UI with slide-to-dismiss.
  widgets/
    reloj_widget.dart                # Real-time clock display (unused in main UI).
    tarjeta_alarma.dart              # Alarm card with Dismissible (swipe to delete).
    dialogo_alarma.dart              # Floating dialog: create/edit alarms (unified).
    slide_desbloqueo.dart            # Random-direction slide-to-unlock widget.
  utils/
    constantes.dart                  # Global constants (audio filename, day names, storage keys).
    date_utils.dart                  # Date calculations, time formatting (12h AM/PM), random direction.
```

**MVP flow:** View calls presenter methods → presenter manipulates models/services → presenter calls back via `AlarmasView` interface → View updates via `setState()`.

## Key dependencies

| Package | Purpose |
|---|---|
| `alarm` ^5.2.1 | Native alarm scheduling. Has NO built-in UI — we build our own ringing screen. |
| `permission_handler` ^11.0.0 | SCHEDULE_EXACT_ALARM permission on Android 12+. |
| `shared_preferences` ^2.2.0 | Local persistence for alarm list + nextId. |
| `do_not_disturb` ^1.0.3 | Checks if DND mode is active (may silence alarms). |
| `path_provider` ^2.1.0 | Gets Documents directory for generated WAV file. |

## Critical gotchas

- **`alarm` package has no UI.** The `Alarm.ringing` stream emits `AlarmSet`. You must listen to it and navigate to your own fullscreen widget. We do this in `AlarmasPresenter._iniciarEscuchaRinging()`.
- **Audio file is generated at runtime.** `AudioService.prepararSonido()` creates a WAV sweep in the Documents directory. Must run before `Alarm.init()`. This is done in `main()`.
- **Stale test:** `test/widget_test.dart` asserts on old UI text. The current UI shows "No tienes alarmas" with subtext "Toca + para crear tu primera alarma". Update before running `flutter test`.
- **PopScope, not WillPopScope.** `pantalla_alarma_activa.dart` uses `PopScope(canPop: false)` to prevent back navigation during ringing.
- **`AlarmSet` lives in `alarm/utils/alarm_set.dart`.** Must import explicitly: `import 'package:alarm/utils/alarm_set.dart';`
- **Time picker uses AM/PM format.** No `alwaysUse24HourFormat` override.
- **Create/Edit use unified `DialogoAlarma`.** Shows as floating centered dialog. Two-step flow: hour first → "Configurar" expands to name + days.
- **Delete uses SnackBar with "Deshacer"** (not confirmation dialog). Prevents Dismissible rebuild errors.

## Conventions

- All variable names, comments, and UI strings are in **Spanish**.
- Day numbering follows `DateTime.weekday`: 1=Monday (Lun) through 7=Sunday (Dom).
- `flutter_lints` default rules — no custom overrides in `analysis_options.yaml`.
- `flutter analyze` must pass with **zero issues** (errors, warnings, and infos).
- Cards use `RepaintBoundary` to avoid unnecessary repaints.
- Alarm cards show a "HOY" badge when the alarm fires on the current day.
- Dynamic icons per time of day: ☀️ morning, 🌤️ afternoon, 🌙 evening, 🌜 night.
- Haptic feedback on key actions: toggle, save, select day, pick time.
