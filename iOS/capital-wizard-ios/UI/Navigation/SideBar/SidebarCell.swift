//
//  SidebarCell.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit

class SidebarCell: UITableViewCell {
    struct Identifier {
        static var collapsed = "CollapsedCell"
        static var expanded  = "ExpandedCell"
    }
    
    private enum CellType {
        case collapsed
        case expanded
    }
    
    private var type: CellType
    
    private var icon:  ApplicationIconView?
    private var title: UILabel?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        if let reuseIdentifier = reuseIdentifier, reuseIdentifier == Identifier.expanded {
            type = .expanded
        } else {
            type = .collapsed
        }
        
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        setupCell()
    }
    
    required init?(coder: NSCoder) {
        type = .collapsed
        super.init(coder: coder)
    }
    
    func updateCell(icon: UIImage?,
                    tintColor: UIColor,
                    backgroundColor: UIColor,
                    badge: Int) {
        self.icon?.update(icon: icon, tintColor: tintColor, backgroundColor: backgroundColor)
        self.icon?.setBadge(badge)
    }
    
    func updateCell(icon: UIImage?,
                    tintColor: UIColor,
                    backgroundColor: UIColor,
                    title: String,
                    badge: Int) {
        self.title?.text = title
        self.icon?.update(icon: icon, tintColor: tintColor, backgroundColor: backgroundColor)
        self.icon?.setBadge(badge)
    }
    
    private func setupCell() {
        self.backgroundColor = .clear
        
        let icon  = ApplicationIconView()
        self.icon = icon
        contentView.addSubview(icon)
        
        icon.addConstraint(to: contentView, sizeMultiplier: 0.75)
        
        icon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor).isActive = true

        if type == .expanded {
            let title  = UILabel()
            title.text = ""
            self.title = title
            
            contentView.addSubview(title)
            
            icon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6.875).isActive = true
            
            title.translatesAutoresizingMaskIntoConstraints = false
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8).isActive = true
            title.trailingAnchor.constraint(equalTo: contentView.trailingAnchor).isActive = true
            title.centerYAnchor.constraint(equalTo: contentView.centerYAnchor).isActive = true
        } else {
            icon.centerXAnchor.constraint(equalTo: contentView.centerXAnchor).isActive = true
        }
    }
}

class ProfileSideBarCell: UITableViewCell {
    struct Identifier {
        static var collapsed = "ProfileCollapsedCell"
        static var expanded  = "ProfileExpandedCell"
    }
    
    private enum CellType {
        case collapsed
        case expanded
    }
    
    private var type:   CellType
    private var avatar: UIImageView?
    private var title:   UILabel?
    
    var button: UIButton?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        if let reuseIdentifier = reuseIdentifier, reuseIdentifier == Identifier.expanded {
            type = .expanded
        } else {
            type = .collapsed
        }
        
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        setupCell()
    }
    
    required init?(coder: NSCoder) {
        type = .collapsed
        super.init(coder: coder)
    }
    
    func updateCell(icon: UIImage?, borderColor: UIColor, name: String = "") {
        avatar?.image = icon
        title?.text   = name
        avatar?.layer.borderColor = borderColor.cgColor
    }
    
    private func setupCell() {
        self.backgroundColor = .clear
        
        let imageView = RoundImageView(image: nil)
        
        
        
        self.avatar = imageView
        contentView.addSubview(imageView)
        
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        imageView.heightAnchor.constraint(equalTo: contentView.heightAnchor, multiplier: 0.7).isActive = true
        imageView.widthAnchor.constraint(equalTo: imageView.heightAnchor).isActive = true
        imageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor).isActive = true
        if type == .expanded {
            let title  = UILabel()
            title.text = "Profile"
            self.title = title
            
            contentView.addSubview(title)
            
            let button = UIButton()
            
            let icon = ApplicationIconView()
            icon.update(icon: UIImage(named: "gear")?.withRenderingMode(.alwaysTemplate),
                        tintColor: .label,
                        backgroundColor: .lightGray.withAlphaComponent(0.2))
            icon.isUserInteractionEnabled = false
            icon.isHidden = true
            button.addSubview(icon)
            
            contentView.addSubview(button)
            
            self.button = button
            button.translatesAutoresizingMaskIntoConstraints = false
            
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8.25).isActive = true

            title.translatesAutoresizingMaskIntoConstraints = false
            title.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8).isActive = true
            title.centerYAnchor.constraint(equalTo: contentView.centerYAnchor).isActive = true
            
            button.heightAnchor.constraint(equalTo: contentView.heightAnchor, multiplier: 0.9).isActive = true
            button.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 100.5).isActive = true
            button.centerYAnchor.constraint(equalTo: contentView.centerYAnchor).isActive = true
            
            icon.addConstraint(to: contentView, sizeMultiplier: 0.75)
            
            icon.centerYAnchor.constraint(equalTo: button.centerYAnchor).isActive = true
            icon.centerXAnchor.constraint(equalTo: button.centerXAnchor).isActive = true
        } else {
            imageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor).isActive = true
        }
        imageView.layer.cornerRadius = imageView.frame.width/2.0
        imageView.layer.masksToBounds = false
        imageView.layer.borderWidth = 3
        imageView.layer.borderColor = UIColor.clear.cgColor
        imageView.clipsToBounds = true
    }
}
