package com.capitalwizard.android

import android.app.Application
import com.capitalwizard.android.services.AuthService
import com.capitalwizard.android.utils.ServiceManager
import com.capitalwizard.android.utils.ThemePrefs

class CapitalWizardApp : Application() {

    override fun onCreate() {
        super.onCreate()

        // Apply the stored theme override (defaults to following the system).
        ThemePrefs.apply(this)

        ServiceManager.register(AuthService(this))
    }
}
