import java.util.Properties
import java.io.FileInputStream

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.serialization)
}

// Firebase Cloud Messaging is configured entirely by `app/google-services.json`,
// which is not in source control. The google-services plugin HARD-FAILS the build
// when that file is missing, so it is applied only when the file is there: a
// checkout without Firebase credentials still builds and runs, it just has no
// push token to hand over (PushService reports that and moves on).
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

val keystorePropertiesFile = rootProject.file("keystore.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(FileInputStream(keystorePropertiesFile))
    }
}
// ─────────────────────────────────────────────────────

android {
    namespace = "com.capitalwizard.android"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.capitalwizard.android"
        minSdk = 26
        // Google Play requires targeting within one year of the latest Android
        // release (API 36 from 2026-08-31, and rolling forward each August).
        targetSdk = 36
        versionCode = 2
        versionName = "1.1"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        manifestPlaceholders["appAuthRedirectScheme"] = "capital-wizard-android"
    }

    signingConfigs {
        create("release") {
            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
            storePassword = keystoreProperties["storePassword"] as String?
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
        }
    }
    // ────────────────────────────────────────

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = signingConfigs.getByName("release")
            // ──────────────────────────────────────────
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        viewBinding = true
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
    implementation(libs.androidx.activity)
    implementation(libs.androidx.constraintlayout)
    implementation(libs.androidx.webkit)
    implementation(libs.androidx.splashscreen)
    implementation(libs.androidx.lifecycle.runtime)

    // Firebase Cloud Messaging (push). Harmless without google-services.json —
    // the SDK simply never initialises.
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.messaging)

    // Supabase
    implementation(platform(libs.supabase.bom))
    implementation(libs.supabase.gotrue)

    // Ktor (HTTP client for Supabase)
    implementation(libs.ktor.client.android)

    // Serialization
    implementation(libs.kotlinx.serialization.json)

    // Google Sign-In via Credential Manager
    implementation(libs.credentials)
    implementation(libs.credentials.play)
    implementation(libs.googleid)
}