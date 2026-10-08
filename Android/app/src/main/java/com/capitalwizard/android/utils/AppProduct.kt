package com.capitalwizard.android.utils

import com.capitalwizard.android.BuildConfig

/** Build-time identity, mirroring iOS AppProduct. The web cannot change it. */
object AppProduct {
    val isCodingLab = BuildConfig.CODING_LAB
    val siteHost = if (isCodingLab) "coding-lab.co" else "capital-wizard.com"
    val appHost = "app.$siteHost"
    val developmentHost = "dev.$siteHost"
    val urlScheme = if (isCodingLab) "coding-lab-android" else "capital-wizard-android"
    // The existing sandbox catalog belongs to Capital Wizard's store listing.
    val supportsStoreBilling = !isCodingLab
}
