package com.capitalwizard.android.utils

/**
 * C#-style event system matching the iOS Event<T> pattern.
 */
class Event<T> {

    private val listeners = mutableListOf<EventCallback<T>>()

    val listenerCount: Int get() = listeners.size

    fun subscribe(callback: EventCallback<T>) {
        listeners.add(callback)
    }

    fun unsubscribe(callback: EventCallback<T>) {
        listeners.remove(callback)
    }

    fun invoke(value: T) {
        listeners.forEach { it.invoke(value) }
    }

    operator fun plusAssign(callback: EventCallback<T>) = subscribe(callback)
    operator fun minusAssign(callback: EventCallback<T>) = unsubscribe(callback)
}

class EventCallback<T>(private val action: (T) -> Unit) {

    fun invoke(value: T) {
        action(value)
    }
}
