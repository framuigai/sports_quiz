// android/app/build.gradle.kts
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")          // Kotlin (correct ID for Kotlin DSL)
    // The Flutter Gradle Plugin must be applied after Android & Kotlin
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase / Google Services
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.sports_quiz"

    // Provided by Flutter plugin
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.example.sports_quiz"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Use Java 17 to match AGP + Kotlin + Flutter
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        release {
            // Use debug signing for now so `flutter run --release` works
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    // Flutter project root (two levels up from android/)
    source = "../.."
}
