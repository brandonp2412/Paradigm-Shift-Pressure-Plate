import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val ciSigningPropertiesFile = System.getenv("FLOORSENSE_SIGNING_PROPERTIES")?.let { file(it) }
val ciSigningStoreFile = System.getenv("FLOORSENSE_SIGNING_STORE")?.let { file(it) }
val ciSigningProperties = Properties()
val hasCiSigning = ciSigningPropertiesFile?.isFile == true && ciSigningStoreFile?.isFile == true
if (hasCiSigning) {
    ciSigningPropertiesFile!!.inputStream().use { input -> ciSigningProperties.load(input) }
}

android {
    namespace = "com.floorsense.floorsense_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications (uses java.time APIs).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.floorsense.floorsense_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasCiSigning) {
            create("ciRelease") {
                storeFile = requireNotNull(ciSigningStoreFile)
                storePassword = ciSigningProperties.getProperty("storePassword")
                keyAlias = ciSigningProperties.getProperty("keyAlias")
                keyPassword = ciSigningProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Official repository releases receive signing material through
            // CI environment variables. Local/fork builds fall back to the
            // standard debug signer so contributors can build without secrets.
            signingConfig = if (hasCiSigning) {
                signingConfigs.getByName("ciRelease")
            } else {
                signingConfigs.getByName("debug")
            }
            // Keep WorkManager/Room (workmanager plugin) and notification classes
            // that are accessed reflectively, so R8 doesn't strip them.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
