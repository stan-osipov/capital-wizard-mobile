//
//  Queue.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//
protocol Queueable {
    associatedtype Element
    func peek() -> Element?
    mutating func push(_ element: Element)
    @discardableResult mutating func first() -> Element?
    func contains(_ elemment: Element) -> Bool
    @discardableResult mutating func remove(_ element: Element) -> Element?
}

extension Queueable {
    var isEmpty: Bool { peek() == nil }
}

struct Queue<Element>: Queueable where Element: Equatable {
    private var storage: Array<Element> = []
    
    func peek() -> Element? {
        storage.first
    }
    
    mutating func push(_ element: Element) {
        storage.append(element)
    }
    
    @discardableResult mutating func first() -> Element? {
        guard !storage.isEmpty else {
            return nil
        }
        return storage.removeFirst()
    }
    
    func contains(_ elemment: Element) -> Bool {
        storage.contains(elemment)
    }
    
    mutating func remove(_ element: Element) -> Element? {
        guard let index = storage.firstIndex(of: element) else {
            return nil
        }
        
        return storage.remove(at: index)
    }
    
    mutating func removeAll() {
        storage.removeAll()
    }
}

extension Queue: Equatable {
    static func == (lhs: Queue<Element>, rhs: Queue<Element>) -> Bool { lhs.storage == rhs.storage }
}

extension Queue: CustomStringConvertible {
    var description: String { "\(storage)" }
}
    
extension Queue: ExpressibleByArrayLiteral {
    init(arrayLiteral elements: Self.Element...) { storage = elements }
}
