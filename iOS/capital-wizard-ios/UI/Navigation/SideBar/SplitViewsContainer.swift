//
//  SplitViewsContainer.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit

class SplitViewsContainer: UIViewController {
    private var currentChildControllers: [UIViewController] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemBackground
        
        navigationController?.setNavigationBarHidden(true, animated: false)
    }
    
    
    func cleanUp() {
        for vc in currentChildControllers {
            vc.willMove(toParent: nil)
            vc.view.removeFromSuperview()
            vc.removeFromParent()
        }
        
        currentChildControllers = []
    }

    func setViewControllers(_ viewControllers: [UIViewController], animated: Bool = false, needUpdate: Bool = false) {
        guard viewControllers.count == 1 || viewControllers.count == 2 else {
            print("SecondarySplitViewController supports only 1 or 2 child view controllers.")
            return
        }
        
        for vc in currentChildControllers {
            vc.willMove(toParent: nil)
            vc.view.removeFromSuperview()
            vc.removeFromParent()
        }
        
        currentChildControllers = viewControllers

        addChild(controllers: viewControllers, hasAnimation: animated)
    }

    private func addChild(controllers: Array<UIViewController>, hasAnimation animated: Bool) {
        for (index, vc) in controllers.enumerated() {
            addChild(vc)
            view.addSubview(vc.view)
            vc.didMove(toParent: self)

            vc.view.translatesAutoresizingMaskIntoConstraints = false

            if controllers.count == 1 {
                NSLayoutConstraint.activate([
                    vc.view.topAnchor.constraint(equalTo: view.topAnchor),
                    vc.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                    vc.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    vc.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
                ])
            } else {
                let isLeft = (index == 0)
                NSLayoutConstraint.activate([
                    vc.view.topAnchor.constraint(equalTo: view.topAnchor),
                    vc.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                    vc.view.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.5),
                    isLeft ?
                        vc.view.leadingAnchor.constraint(equalTo: view.leadingAnchor) :
                        vc.view.leadingAnchor.constraint(equalTo: view.centerXAnchor)
                ])
            }
        }

        if animated {
            UIView.animate(withDuration: 0.3) {
                self.view.layoutIfNeeded()
            }
        }
    }
}
