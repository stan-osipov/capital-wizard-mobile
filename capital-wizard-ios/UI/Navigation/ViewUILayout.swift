//
//  ViewUILayout.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit

enum ViewUILayout {
    case split(left: BarItem?, right: BarItem?)
    case wide(BarItem)
    
    case none
    
    mutating func trySetWide(item: BarItem) -> Array<BarItem> {
        var removedItems: Array<BarItem> = []
        switch self {
        case .wide(let wideItem):
            removedItems.append(wideItem)
        case .split(left: let left, right: let right):
            if let left = left, left.id != item.id {
                removedItems.append(left)
            }
            if let right = right, right.id != item.id {
                removedItems.append(right)
            }
        case .none: break
        }
        self = .wide(item)
        return removedItems
    }
    
    mutating func trySetAnySplit(item: BarItem) -> BarItem? {
        switch self {
        case .wide(let wideItem):
            guard wideItem.id != item.id else {
                return nil
            }
            if wideItem.layout.contains(.right) {
                self = .split(left: item, right: wideItem)
            } else {
                self = .wide(item)
                return wideItem
            }
        case .split(left: let left, right: let right):
            if let left = left, left.id == item.id {
                return nil
            }
            if let right = right, right.id == item.id {
                return nil
            }
            
            if let right = right {
                self = .split(left: item, right: right)
                return left
            } else if let left = left, left.layout.contains(.right) {
                self = .split(left: item, right: left)
                return right
            } else {
                self = .wide(item)
                return right
            }
        case .none:
            self = .wide(item)
        }
        return nil
    }
    
    mutating func trySetSplitLeft(item: BarItem) -> BarItem? {
        switch self {
        case .wide(let wideItem):
            guard wideItem.id != item.id else {
                return nil
            }
            if wideItem.layout.contains(.right) {
                self = .split(left: item, right: wideItem)
            } else {
                self = .wide(item)
                return wideItem
            }
        case .split(left: let left, right: let right):
            if let left = left, left.id == item.id {
                return nil
            }
            
            if let right = right {
                self = .split(left: item, right: right)
                return left
            } else if let left = left, left.layout.contains(.right) {
                self = .split(left: item, right: left)
                return right
            } else {
                self = .wide(item)
                return right
            }
        case .none:
            self = .wide(item)
        }
        return nil
    }
    
    mutating func trySetSplitRight(item: BarItem) ->BarItem? {
        switch self {
        case .wide(let wideItem):
            guard wideItem.id != item.id else {
                return nil
            }
            if wideItem.layout.contains(.left) {
                self = .split(left: wideItem, right: item)
            } else {
                self = .wide(item)
                return wideItem
            }
        case .split(left: let left, right: let right):
            if let right = right, right.id == item.id {
                return nil
            }
            
            if let left = left {
                self = .split(left: left, right: item)
                return right
            } else if let right = right, right.layout.contains(.left) {
                self = .split(left: right, right: item)
                return left
            } else {
                self = .wide(item)
                return left
            }
        case .none:
            self = .wide(item)
        }
        return nil
    }
    
    var controllers: Array<UIViewController> {
        switch self {
        case .split(let left, let right):
            var controllers: Array<UIViewController> = []
            
            if let left = left {
                controllers.append(left.vc)
            }
            if let right = right {
                controllers.append(right.vc)
            }
            return controllers
        case .wide(let item):
            return [item.vc]
        case .none:
            return []
        }
    }
}
