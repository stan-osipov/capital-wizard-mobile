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

// Capital Wizard's Firebase client must never be compiled into Coding Lab.
// Until its own client is supplied, the shell reports push as unavailable.
tasks.configureEach {
    if (name.startsWith("processCodingLab") && name.endsWith("GoogleServices")) {
        enabled = file("src/codingLab/google-services.json").exists()
    }
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
        versionCode = 3
        versionName = "1.2"

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
    flavorDimensions += "product"
    productFlavors {
        create("capitalWizard") {
            dimension = "product"
            buildConfigField("boolean", "CODING_LAB", "false")
            manifestPlaceholders["productHost"] = "app.capital-wizard.com"
            manifestPlaceholders["productSiteHost"] = "capital-wizard.com"
            manifestPlaceholders["appAuthRedirectScheme"] = "capital-wizard-android"
        }
        create("codingLab") {
            dimension = "product"
            applicationId = "co.codinglab.android"
            versionCode = 1
            versionName = "1.0"
            buildConfigField("boolean", "CODING_LAB", "true")
            manifestPlaceholders["productHost"] = "app.coding-lab.co"
            manifestPlaceholders["productSiteHost"] = "coding-lab.co"
            manifestPlaceholders["appAuthRedirectScheme"] = "coding-lab-android"
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
        buildConfig = true
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    implementation("com.android.billingclient:billing-ktx:8.3.0")
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
    implementation(libs.androidx.activity)
    implementation(libs.androidx.constraintlayout)
    implementation(libs.androidx.webkit)
    implementation(libs.androidx.browser)
    implementation(libs.androidx.splashscreen)
    implementation(libs.androidx.lifecycle.runtime)

    // Play Install Referrer. Google's store hands the app whatever `referrer`
    // was on the listing URL, ON FIRST LAUNCH AFTER INSTALL — which is how a
    // referral code survives someone tapping a link, installing, and opening
    // the app minutes later. Apple ships nothing equivalent, so iOS has no
    // sibling for InstallReferrerService: there the code is carried by the
    // person (printed on the claim page, typed into sign-up).
    implementation(libs.installreferrer)

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
