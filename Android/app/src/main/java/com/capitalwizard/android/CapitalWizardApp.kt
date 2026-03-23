package com.capitalwizard.android

import android.app.Application
import com.capitalwizard.android.services.AuthService
import com.capitalwizard.android.utils.ServiceManager

class CapitalWizardApp : Application() {

    override fun onCreate() {
        super.onCreate()
        ServiceManager.register(AuthService(this))
    }
}
