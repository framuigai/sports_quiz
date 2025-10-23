// android/settings.gradle.kts
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }

    // Make Flutter's Gradle build logic available
    val props = java.util.Properties()
    val lp = file("local.properties")
    require(lp.exists()) { "local.properties not found. Flutter SDK path is required." }
    lp.inputStream().use { props.load(it) }
    val flutterSdkPath = props.getProperty("flutter.sdk")
    require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")
}

// One place for plugin versions (avoid duplicates elsewhere)
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"

    // Android Gradle Plugin + Kotlin
    id("com.android.application") version "8.6.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false

    // FlutterFire / Google Services
    id("com.google.gms.google-services") version "4.4.2" apply false
}

rootProject.name = "sports_quiz"
include(":app")
