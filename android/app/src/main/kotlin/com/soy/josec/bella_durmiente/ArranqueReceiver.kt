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
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in ACCIONES) return

        val alarmas = try {
            AlarmStorage(context).getSavedAlarms()
        } catch (e: Exception) {
            Log.e(TAG, "No se pudieron leer las alarmas guardadas", e)
            return
        }

        Log.i(TAG, "Reprogramando ${alarmas.size} alarma(s) tras ${intent.action}")

        val api = AlarmApiImpl(context)
        for (alarma in alarmas) {
            try {
                api.setAlarm(alarma)
            } catch (e: Exception) {
                Log.e(TAG, "No se pudo reprogramar la alarma ${alarma.id}", e)
            }
        }
    }
}
