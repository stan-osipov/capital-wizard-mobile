//
//  ExpandedSidebarViewController.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import CoreFoundation
import UIKit

private struct Consts {
    static let backgroundColorAlpha   = 0.3
    
    static let iconWithTextFontSize   = CGFloat(14)
    static let iconWithTextSize       = CGSize(width: 55, height: 55)
    static let iconstWithTextHalfSize = CGSize(width: iconWithTextSize.width/2, height: iconWithTextSize.height/2)
    
    static let closeIconName          = "xmark.circle"
    static let closeIconText          = "Close"
}

class ExpandedSidebarViewController: SidebarController {
    override var type: SideBarType {
        .expanded
    }

    override func setupView() {
        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        blurView.frame = view.bounds
        blurView.layer.cornerRadius  = 10
        blurView.layer.masksToBounds = true
        blurView.layer.maskedCorners = [ .layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        blurView.autoresizingMask    = [.flexibleWidth, .flexibleHeight]
        view.addSubview(blurView)
        
        super.setupView()
        
        view.backgroundColor = view.backgroundColor?.withAlphaComponent(Consts.backgroundColorAlpha)

        tableView.backgroundColor = .clear
        tableView.separatorStyle  = .none
        
        tableView.delegate   = self
        tableView.dataSource = self
        
        tableView.register(SidebarCell.self, forCellReuseIdentifier: SidebarCell.Identifier.expanded)
        tableView.register(ProfileSideBarCell.self, forCellReuseIdentifier: ProfileSideBarCell.Identifier.expanded)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: SideBarConst.topCellIdentifier)
        
        tableView.layer.cornerRadius  = 10
        tableView.layer.masksToBounds = true
        tableView.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        
        self.view.layer.cornerRadius  = 10
        self.view.layer.masksToBounds = true
        self.view.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
    }
    
    override func updateColorScheme(_ scheme: ColorScheme) {
        super.updateColorScheme(scheme)
        view.backgroundColor = view.backgroundColor?.withAlphaComponent(Consts.backgroundColorAlpha)
    }
    
    override func onSwiched() {
        super.onSwiched()
        view.backgroundColor = view.backgroundColor?.withAlphaComponent(Consts.backgroundColorAlpha)
    }
}

extension ExpandedSidebarViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        if section == SideBarConst.topSectionIndex {
            return SideBarConst.topSectionRowsInSection
        } else if section == SideBarConst.baseSectionIndex {
            return dataProvider?.baseItems.count ?? .zero
        } else if section == SideBarConst.staticSectionIndex {
            return dataProvider?.staticItems.count ?? .zero
        } else if section == SideBarConst.dynamicSectionIndex {
            return dataProvider?.dynamicItems.count ?? .zero
        }
        return .zero
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return SideBarConst.sectionsAmout
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: UITableViewCell
        
        if indexPath.section == SideBarConst.baseSectionIndex && indexPath.row == 0 {
            cell = tableView.dequeueReusableCell(withIdentifier: ProfileSideBarCell.Identifier.expanded,
                                                 for: indexPath)
        } else if indexPath.section == SideBarConst.baseSectionIndex ||
            indexPath.section == SideBarConst.dynamicSectionIndex ||
            indexPath.section == SideBarConst.staticSectionIndex {
            cell = tableView.dequeueReusableCell(withIdentifier: SidebarCell.Identifier.expanded,
                                                 for: indexPath)
        } else {
            cell = tableView.dequeueReusableCell(withIdentifier: SideBarConst.topCellIdentifier,
                                                 for: indexPath)
        }
        
        if indexPath.section == SideBarConst.topSectionIndex {
            cell.selectionStyle   = .default
            cell.backgroundColor  = .clear
            cell.tintColor        = isDarkMode ? .white : .black
            cell.textLabel?.text  = ""
            cell.imageView?.image = UIImage(systemName: SideBarConst.topCellIconName)
            
        } else if indexPath.section == SideBarConst.baseSectionIndex {
            guard let item = dataProvider?.baseItems[indexPath.row] else {
                return cell
            }
            if indexPath.row == 0, let cell = cell as? ProfileSideBarCell {
                let border = isDarkMode ? CustomTabBarConst.darkBackgroundColor : CustomTabBarConst.lightBackgroundColor
                cell.updateCell(icon: item.icon, borderColor: item.isSelected ? border : .clear, name: item.name)
            } else if  let cell = cell as? SidebarCell {
                guard let item = dataProvider?.baseItems[indexPath.row] else {
                    return cell
                }
                updateCell(cell, with: item)
            }
        } else if indexPath.section == SideBarConst.staticSectionIndex, let cell = cell as? SidebarCell {
            guard let item = dataProvider?.staticItems[indexPath.row] else {
                return cell
            }
            
            updateCell(cell, with: item)
        } else if indexPath.section == SideBarConst.dynamicSectionIndex, let cell = cell as? SidebarCell {
            guard let item = dataProvider?.dynamicItems[indexPath.row] else {
                return cell
            }
            
            updateCell(cell, with: item)
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }
    
   
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        var customActions: Array<UIContextualAction> = []
        if indexPath.section == SideBarConst.topSectionIndex {
            return nil
        } else if indexPath.section == SideBarConst.baseSectionIndex {
            if indexPath.row == 1 {
                return nil
            }
            customActions.append(contentsOf: actionsForProfile())
        } else {
            customActions.append(contentsOf: actions(for: indexPath))
        }

        let config = UISwipeActionsConfiguration(actions: customActions)
        config.performsFirstActionWithFullSwipe = false
        return config
    }
    
    private func actionsForProfile() -> Array<UIContextualAction> {
        let profileIndex = IndexPath(row: 0, section: SideBarConst.baseSectionIndex)
        
        let closeAction = UIContextualAction(style: .normal, title: nil) { [weak self] action, view, callback in
            self?.delegate?.onCloseClicked(for: profileIndex)
            callback(true)
        }
        closeAction.backgroundColor = .systemOrange
        if let image = UIImage(systemName: Consts.closeIconName) {
            closeAction.image = makeIconWithText(text: Consts.closeIconText, image: image)
        } else {
            closeAction.title = Consts.closeIconText
        }
        
        return [closeAction]
    }
    
    private func actions(for indexPath: IndexPath) -> Array<UIContextualAction> {
        let closeAction = UIContextualAction(style: .normal, title: nil) { [weak self] action, view, callback in
            self?.delegate?.onCloseClicked(for: indexPath)
            callback(true)
        }
        closeAction.backgroundColor = .systemOrange
        if let image = UIImage(systemName: Consts.closeIconName) {
            closeAction.image = makeIconWithText(text: Consts.closeIconText, image: image)
        } else {
            closeAction.title = Consts.closeIconText
        }
        
        return [closeAction]
    }
    
    private func makeIconWithText(text: String, image: UIImage) -> UIImage {
        let size = Consts.iconWithTextSize
        
        let imageView = UIImageView(image: image)
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.heightAnchor.constraint(equalToConstant: Consts.iconstWithTextHalfSize.height).isActive = true
        
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: Consts.iconWithTextFontSize, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.heightAnchor.constraint(equalToConstant: Consts.iconstWithTextHalfSize.height).isActive = true
        
        let stack = UIStackView(arrangedSubviews: [imageView, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.distribution = .fillEqually
        stack.frame = CGRect(origin: .zero, size: size)
        
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            stack.layer.render(in: ctx.cgContext)
        }
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        guard section != SideBarConst.topSectionIndex else {
            return 0
        }
        return 1
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard section != SideBarConst.topSectionIndex else {
            return nil
        }
        let line = UIView()
        line.backgroundColor = .separator
        return line
    }
}

extension ExpandedSidebarViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == SideBarConst.topSectionIndex {
            delegate?.collapseSidebar()
        } else if indexPath.section == SideBarConst.baseSectionIndex   ||
                  indexPath.section == SideBarConst.staticSectionIndex ||
                  indexPath.section == SideBarConst.dynamicSectionIndex {

            delegate?.onItemPick(indexPath: indexPath)
        }
    }
}
