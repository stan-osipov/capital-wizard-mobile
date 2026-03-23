//
//  ApplicationViewController.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit

class ApplicationViewController: UIViewController {

    private lazy var windowService: WindowsService? = ServiceManager.shared.getService()

    weak var application: Application?
}

extension ApplicationViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
