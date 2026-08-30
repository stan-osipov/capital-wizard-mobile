package com.capitalwizard.android

import android.app.Application
import android.os.Build
import com.capitalwizard.android.services.AuthService
import com.capitalwizard.android.services.DeepLinkService
import com.capitalwizard.android.services.InstallReferrerService
import com.capitalwizard.android.services.PushService
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
        ServiceManager.register(DeepLinkService(this))
        ServiceManager.register(PushService())

        // A referral code that came through a Play install. Fire-and-forget and
        // read once per install; it stashes a route on DeepLinkService exactly
        // as an inbound link would, so the WebView opens on sign-up with the
        // code attached. No iOS sibling — Apple hands an app nothing at install
        // time, so there the code travels with the person instead.
        InstallReferrerService(this).checkOnce(ServiceManager.getService<DeepLinkService>())

        // The channel has to exist before the first notification lands, which can
        // be long before anything else in the app runs.
        PushService.ensureChannel(this)
    }
}
