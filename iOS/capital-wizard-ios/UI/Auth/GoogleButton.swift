//
//  GoogleButton.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit

class GoogleButton: UIButton {
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupButton()
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    private func setupButton() {
        backgroundColor = .white
        layer.cornerRadius = 8
        setTitleColor(.black, for: .normal)
        titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        
        let gLabel = UILabel()
        gLabel.text = "G"
        gLabel.font = .systemFont(ofSize: 20, weight: .bold)
        gLabel.textColor = UIColor(red: 66/255, green: 133/255, blue: 244/255, alpha: 1)
        gLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gLabel)
        
        NSLayoutConstraint.activate([
            gLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            gLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 60)
        ])
        
        addTarget(self, action: #selector(touchDown), for: .touchDown)
        addTarget(self, action: #selector(touchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }
    
    @objc private func touchDown() {
        UIView.animate(withDuration: 0.1) {
            self.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
            self.backgroundColor = UIColor(white: 0.95, alpha: 1)
        }
    }
    
    @objc private func touchUp() {
        UIView.animate(withDuration: 0.1) {
            self.transform = .identity
            self.backgroundColor = .white
        }
    }
}