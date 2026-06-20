package com.soy.josec.bella_durmiente

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val canal = "mi_despertador/sistema"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, canal)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // ¿Puede la app mostrar pantallas a pantalla completa sobre el
                    // lockscreen? En Android 14+ el usuario debe concederlo a mano.
                    "puedeUsarFullScreenIntent" -> {
                        if (Build.VERSION.SDK_INT >= 34) {
                            val nm = getSystemService(Context.NOTIFICATION_SERVICE)
                                as NotificationManager
                            result.success(nm.canUseFullScreenIntent())
                        } else {
                            result.success(true)
                        }
                    }
                    // Abre el ajuste del sistema para conceder full-screen intent.
                    "abrirAjustesFullScreenIntent" -> {
                        if (Build.VERSION.SDK_INT >= 34) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT
                            )
                            intent.data = Uri.parse("package:$packageName")
                            startActivity(intent)
                        }
                        result.success(null)
                    }
                    // Intenta abrir la pantalla de "Inicio automático" (Autostart) del
                    // fabricante. Si no existe, cae a los ajustes de la app.
                    "abrirAutostartOEM" -> {
                        val intents = listOf(
                            Intent().setClassName(
                                "com.miui.securitycenter",
                                "com.miui.permcenter.autostart.AutoStartManagementActivity"
                            ),
                            Intent().setClassName(
                                "com.miui.securitycenter",
                                "com.miui.permcenter.autostart.AutoStartDetailManagementActivity"
                            ),
                            Intent().setClassName(
                                "com.huawei.systemmanager",
                                "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
                            ),
                            Intent().setClassName(
                                "com.coloros.safecenter",
                                "com.coloros.safecenter.permission.startup.StartupAppListActivity"
                            ),
                            Intent().setClassName(
                                "com.vivo.permissionmanager",
                                "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
                            )
                        )
                        var abierto = false
                        for (i in intents) {
                            try {
                                startActivity(i)
                                abierto = true
                                break
                            } catch (e: Exception) {
                                // Probar el siguiente componente.
                            }
                        }
                        if (!abierto) {
                            startActivity(
                                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                                    .setData(Uri.parse("package:$packageName"))
                            )
                        }
                        result.success(abierto)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
