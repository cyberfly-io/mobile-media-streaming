plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.cyberfly_streaming"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.cyberfly_streaming"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24  // Required for FFmpegKit
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

configurations.all {
    resolutionStrategy {
        // Force CameraX to stable version 1.3.4 to avoid beta01 compilation issues
        force("androidx.camera:camera-core:1.3.4")
        force("androidx.camera:camera-camera2:1.3.4")
        force("androidx.camera:camera-lifecycle:1.3.4")
        force("androidx.camera:camera-video:1.3.4")
        force("androidx.concurrent:concurrent-futures:1.2.0")
    }
}

dependencies {
    implementation("androidx.concurrent:concurrent-futures:1.2.0")
    implementation("com.google.guava:guava:32.1.3-android")
}

flutter {
    source = "../.."
}
