import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firma de release. key.properties y el keystore NO están en git (son secretos).
// Si falta el archivo, la configuración del proyecto no debe explotar: `flutter run`,
// los builds debug/profile y los tests de Android tienen que seguir funcionando.
// Pero un APK/AAB de release NUNCA debe salir firmado con la clave de debug en
// silencio: ver la tarea de verificación al final de este archivo.
val keyPropertiesFile = rootProject.file("key.properties")
val hayClaveDeFirma = keyPropertiesFile.exists()
val keyProperties = Properties()
if (hayClaveDeFirma) {
    keyPropertiesFile.inputStream().use { keyProperties.load(it) }
}

android {
    namespace = "com.soy.josec.bella_durmiente"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.soy.josec.bella_durmiente"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hayClaveDeFirma) {
            create("release") {
                keyAlias = keyProperties["keyAlias"] as String
                keyPassword = keyProperties["keyPassword"] as String
                storeFile = file(keyProperties["storeFile"] as String)
                storePassword = keyProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Sin key.properties no se asigna NINGUNA firma (y en concreto no la de
            // debug): el empaquetado de release se detiene más abajo.
            if (hayClaveDeFirma) {
                signingConfig = signingConfigs.getByName("release")
            }

            // R8 + recorte de recursos. El plugin de Flutter ya los activa por defecto
            // en release; se declaran aquí para que no dependan de ese valor por
            // defecto y para que proguard-rules.pro quede visible. Las reglas de los
            // paquetes (alarm, Gson, kotlinx.serialization, AdMob…) llegan solas como
            // consumer rules; proguard-rules.pro solo añade las de esta app.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

// Sin key.properties, empaquetar un APK o un AAB de release falla con un mensaje
// claro en vez de producir un artefacto sin firma o firmado con la clave de debug.
// Se engancha a las tareas de empaquetado (no a la configuración) para que todo lo
// demás —incluida la compilación y R8— siga funcionando sin el archivo.
if (!hayClaveDeFirma) {
    tasks.matching { it.name == "packageRelease" || it.name == "packageReleaseBundle" }
        .configureEach {
            doFirst {
                throw GradleException(
                    "Falta android/key.properties: no se puede firmar el release. " +
                        "Crea el archivo con storeFile, storePassword, keyAlias y keyPassword " +
                        "(ver https://docs.flutter.dev/deployment/android#signing-the-app). " +
                        "No se firma con la clave de debug a propósito: un artefacto así no " +
                        "sirve para publicar y podría confundirse con uno válido."
                )
            }
        }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
