plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    // Applied conditionally in app/build.gradle.kts — declaring it here only
    // puts it on the classpath.
    alias(libs.plugins.google.services) apply false
}
