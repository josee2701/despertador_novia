package com.soy.josec.bella_durmiente

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.gdelataillade.alarm.api.AlarmApiImpl
import com.gdelataillade.alarm.services.AlarmStorage

/**
 * Reprograma las alarmas tras un arranque rápido o una actualización de la app.
 *
 * El BootReceiver del package `alarm` solo atiende ACTION_BOOT_COMPLETED, que
 * MIUI y HONOR no siempre entregan cuando el arranque es "rápido". Sin esto,
 * las alarmas se pierden en silencio tras reiniciar el teléfono.
 *
 * Depende de clases internas de `alarm` 5.2.1: revisar si se sube de versión.
 */
class ArranqueReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "ArranqueReceiver"

        private val ACCIONES = setOf(
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON",
            Intent.ACTION_MY_PACKAGE_REPLACED
        )

        /**
         * Desplazamiento con el que las versiones ANTIGUAS de la app
         * programaban el aviso de "suena en 30 minutos" como alarma nativa.
         *
         * Hoy ese aviso es una notificación local y la app ya no crea ningún
         * ID por encima de este valor. Rearmar uno de los heredados que quedan
         * en el AlarmStorage de la versión vieja reproduce el bug original: el
         * recordatorio dispara, deja vivo el foreground service con
         * `ringingAlarmIds` ocupado y el package descarta la alarma real de la
         * mañana. Por eso se saltan aquí.
         */
        private const val OFFSET_RECORDATORIO_HEREDADO = 10000
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in ACCIONES) return

        // AlarmStorage usa runBlocking sobre DataStore, tanto al leer como al
        // guardar cada alarma. Hacerlo en el hilo principal consume el
        // presupuesto de ~10 s del broadcast y puede provocar un ANR con
        // varias alarmas guardadas. goAsync() permite salir del hilo principal
        // manteniendo vivo el proceso hasta llamar a finish().
        val pendiente = goAsync()
        val accion = intent.action
        Thread {
            try {
                reprogramarAlarmas(context, accion)
            } catch (e: Exception) {
                Log.e(TAG, "Fallo al reprogramar tras $accion", e)
            } finally {
                // Debe liberarse en TODOS los caminos, también en el de error:
                // un PendingResult sin finish() deja el proceso retenido.
                pendiente.finish()
            }
        }.start()
    }

    private fun reprogramarAlarmas(context: Context, accion: String?) {
        val alarmas = try {
            AlarmStorage(context).getSavedAlarms()
        } catch (e: Exception) {
            Log.e(TAG, "No se pudieron leer las alarmas guardadas", e)
            return
        }

        Log.i(TAG, "Revisando ${alarmas.size} alarma(s) guardada(s) tras $accion")

        val ahora = System.currentTimeMillis()
        val api = AlarmApiImpl(context)
        for (alarma in alarmas) {
            if (alarma.id > OFFSET_RECORDATORIO_HEREDADO) {
                Log.i(
                    TAG,
                    "Recordatorio heredado ${alarma.id} omitido: la app ya no " +
                        "programa avisos como alarmas"
                )
                continue
            }
            // AlarmApiImpl.setAlarm calcula delayInSeconds negativo para una
            // fecha pasada, cae en la rama `<= 5` y llama a
            // handleImmediateAlarm: la alarma sonaría AHORA, a todo volumen,
            // en el momento en que Play Store actualice la app.
            if (alarma.dateTime.time <= ahora) {
                Log.i(
                    TAG,
                    "Alarma ${alarma.id} omitida: su fecha ya pasó y " +
                        "reprogramarla la haría sonar de inmediato"
                )
                continue
            }
            try {
                api.setAlarm(alarma)
            } catch (e: Exception) {
                Log.e(TAG, "No se pudo reprogramar la alarma ${alarma.id}", e)
            }
        }
    }
}
