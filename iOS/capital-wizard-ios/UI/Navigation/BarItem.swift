//
//  BarItem.swift
//  capital-wizard-ios
//
//  Created by Roman on 22.02.2026.
//
import UIKit

struct BarItem {
    let id:   String
    var name: String
    var icon: UIImage?
    let vc:   UIViewController
    
    var isSelected: Bool = false
    var badge:      Int = 0
    
    var layout: ApplicationUILayout
}
 
