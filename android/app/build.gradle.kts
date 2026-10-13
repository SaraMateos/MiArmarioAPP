plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "es.personal.mi_armario"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "es.personal.mi_armario.local"
        // Personal delivery targets the Galaxy S23 (ARM64); also filter ML AARs.
        ndk { abiFilters += "arm64-v8a" }
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    androidResources { noCompress += listOf("tflite", "onnx") }
    signingConfigs {
        getByName("debug") {
            val stableKey = System.getenv("ARMARIO_SIGNING_KEY")
            if (!stableKey.isNullOrBlank()) storeFile = file(stableKey)
        }
    }
    buildTypes {
        release {
            // Personal hotfix: avoid rewriting JNI/reflection boundaries.
            // MediaPipe's AAR also exposes unused optional proto APIs; review
            // those separately before enabling a minimized release again.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            ndk {
                abiFilters.clear()
                abiFilters += "arm64-v8a"
            }
            // Personal trial APK. Configure a stable private release key for long-term use.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // uCrop 2.2.11 AAR references these classes but its published POM omits them.
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.google.mediapipe:tasks-vision:0.10.32")
    implementation("com.google.ai.edge.litert:litert:1.4.2")
    implementation("com.google.ai.edge.litert:litert-api:1.4.2")
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.23.2")
}

flutter {
    source = "../.."
}
