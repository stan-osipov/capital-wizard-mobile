package com.capitalwizard.android

import android.app.Application
import android.os.Build
import com.capitalwizard.android.services.AuthService
import com.capitalwizard.android.utils.CWLog
import com.capitalwizard.android.utils.ServiceManager
import com.capitalwizard.android.utils.ThemePrefs

class CapitalWizardApp : Application() {

    override fun onCreate() {
        super.onCreate()

        val version = try {
            packageManager.getPackageInfo(packageName, 0).versionName
        } catch (e: Exception) {
            "?"
        }
        CWLog.log(
            "App launch — v$version, Android ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT}), ${Build.MANUFACTURER} ${Build.MODEL}",
            category = "App"
        )

        // Apply the stored theme override (defaults to following the system).
        ThemePrefs.apply(this)

        ServiceManager.register(AuthService(this))
    }
}
