//
//  Event.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import Foundation
/*
 Event like in C#
 */
class Event<T>: NSObject {
    
    var listenersCount: Int {
        eventListeners.count
    }
    
    private var eventListeners: Array<EventCallback<T>> = []
    
    static func += (event: Event<T>, callback: EventCallback<T>) {
        event.subscribe(to: callback)
    }
    
    static func -= (event: Event<T>, callback: EventCallback<T>) {
        event.unSubscribe(from: callback)
    }
    
    private func subscribe(to event: EventCallback<T>) {
        eventListeners.append(event)
    }
    
    private func unSubscribe(from event: EventCallback<T>) {
        if eventListeners.contains(event), let index = eventListeners.firstIndex(of: event) {
            eventListeners.remove(at: index)
        }
    }
    
    func invoke(_ value: T) {
        eventListeners.forEach { event in
            event.Invoke(value)
        }
    }
}

/*
 Wrapper for event callback.
 */
class EventCallback<T>: NSObject {
    
    var callback: (T) -> Void
    
    init(_ callback: @escaping (T) -> Void) {
        self.callback = callback
    }
    
    func Invoke(_ value: T) {
        callback(value)
    }
}
