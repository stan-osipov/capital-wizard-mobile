package com.capitalwizard.android.utils

object ServiceManager {

    @PublishedApi
    internal val services = mutableListOf<Any>()

    fun register(service: Any) {
        services.add(service)
    }

    inline fun <reified T> getService(): T? =
        services.firstOrNull { it is T } as? T
}
