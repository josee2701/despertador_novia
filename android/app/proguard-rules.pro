# Reglas de R8 propias de Bella Durmiente.
#
# Contexto: el plugin de Gradle de Flutter YA activa R8 (minify + shrinkResources)
# en release por defecto; build.gradle.kts solo lo deja explícito. Este archivo
# añade únicamente lo que la app necesita por encima de las reglas que traen los
# propios paquetes (consumer rules) y del plugin de Flutter.
#
# Criterio: reglas MÍNIMAS y justificadas. Una regla de más solo cuesta unos KB;
# una de menos puede hacer que una alarma no suene. Por eso las de abajo son
# deliberadamente amplias en lo que toca a alarmas y notificaciones.
#
# No se añaden reglas para Gson, kotlinx.serialization, DataStore ni
# google_mobile_ads: cada librería trae las suyas en su AAR/JAR y R8 no generó
# missing_rules.txt al compilar con esta configuración.

# --- Código propio (MainActivity, ArranqueReceiver) -------------------------
# El sistema instancia ArranqueReceiver y MainActivity por nombre desde el
# manifest. AAPT2 ya genera keep para los componentes del manifest, pero aquí se
# conserva el paquete entero sin renombrar: es poco código y así un receptor o
# un canal de plataforma nuevo no depende de que alguien recuerde una regla.
-keep class com.soy.josec.bella_durmiente.** { *; }

# --- flutter_local_notifications (recordatorio previo) ----------------------
# El plugin serializa con Gson los recordatorios programados (NotificationDetails
# y sus modelos) y los vuelve a leer en ScheduledNotificationReceiver, que el
# sistema invoca por nombre cuando la app está muerta. Ese receptor NO lo declara
# el AndroidManifest del plugin (lo tiene que declarar la app), así que AAPT2 no
# genera keep para él: esta regla es la que lo protege. Si R8 renombra los campos,
# el JSON guardado por una versión no se puede leer en la siguiente y el
# recordatorio se pierde en silencio. Desde la v19 el plugin no publica reglas
# propias (delega en las de Gson), así que se conserva el paquete completo.
-keep class com.dexterous.** { *; }

# --- package `alarm` 5.2.1: clases internas que usa ArranqueReceiver ---------
# ArranqueReceiver llama directamente a AlarmStorage.getSavedAlarms() y a
# AlarmApiImpl.setAlarm(AlarmSettings). El package ya trae como consumer rule
# `-keep class com.gdelataillade.alarm.** { *; }`, así que hoy estas tres líneas
# son REDUNDANTES A PROPÓSITO: si una actualización del package recorta sus
# reglas, el rearmado tras reinicio (MIUI/HONOR) no debe romperse sin avisar.
# Las models.** se leen con kotlinx.serialization desde DataStore: renombrarlas
# impediría leer las alarmas guardadas por una versión anterior.
-keep class com.gdelataillade.alarm.services.AlarmStorage { *; }
-keep class com.gdelataillade.alarm.api.AlarmApiImpl { *; }
-keep class com.gdelataillade.alarm.models.** { *; }

# --- Play Core (componentes diferidos de Flutter) ---------------------------
# El motor de Flutter referencia Play Core aunque esta app no usa componentes
# diferidos. Sin este dontwarn, R8 puede abortar por clases inexistentes.
-dontwarn com.google.android.play.core.**
