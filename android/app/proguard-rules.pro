# Reglas de R8 para la build de release.
# Flutter y los plugins (alarm, google_mobile_ads, permission_handler, etc.)
# ya aportan sus propias reglas de consumidor; aquí solo va lo que falta.

# Flutter referencia Play Core (componentes diferidos) aunque la app no lo usa.
-dontwarn com.google.android.play.core.**

# Canal de plataforma propio de MainActivity.
-keep class com.soy.josec.bella_durmiente.MainActivity { *; }
