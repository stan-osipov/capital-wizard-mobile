//
//  ApplicationCell.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit

protocol ApplicationCellDelegate: NSObjectProtocol {
    func onTapOnCell(_ cell: ApplicationCell)
}

class ApplicationCell: UICollectionViewCell {
    static let identifier: String = "ApplicationCollectionCell"
    
    var id: Int = .zero
    
    private var title: String?
    
    private var view:  ApplicationIconView?
    private var label: UILabel?
    
    private weak var delegate: ApplicationCellDelegate?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super .init(coder: coder)
        setupView()
    }
    
    func setupCell(image: UIImage?,
                   name: String,
                   id: Int,
                   delegate: ApplicationCellDelegate? = nil,
                   withColor color: UIColor,
                   backgoundColor: UIColor = .lightGray.withAlphaComponent(0.2),
                   imageColor: UIColor) {
        self.delegate = delegate
        
        self.id = id
        
        view?.update(icon: image, tintColor: imageColor, backgroundColor: backgoundColor)
        
        self.label?.text          = name
        self.label?.textColor     = color
    }
    
    private func setupView() {
        contentView.backgroundColor = .clear
        
        let view = ApplicationIconView()
        contentView.addSubview(view)
        
        view.addConstraint(to: contentView, sizeMultiplier: 0.5)
        view.centerXAnchor.constraint(equalTo: contentView.centerXAnchor).isActive = true
        view.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10).isActive = true
        
        self.view = view
        
        let label  = UILabel()
        label.text = ""
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.numberOfLines = 2
        label.font = .systemFont(ofSize: 12)
        
        contentView.addSubview(label)
        
        label.translatesAutoresizingMaskIntoConstraints = false
        
        label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor).isActive = true
        label.widthAnchor.constraint(equalTo: contentView.widthAnchor).isActive = true
        label.topAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: 5).isActive = true
        
        self.label = label
        
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(onTapHandler))
        tap.numberOfTapsRequired = 1
        contentView.addGestureRecognizer(tap)
    }
    
    @objc private func onTapHandler() {
        delegate?.onTapOnCell(self)
    }
}
