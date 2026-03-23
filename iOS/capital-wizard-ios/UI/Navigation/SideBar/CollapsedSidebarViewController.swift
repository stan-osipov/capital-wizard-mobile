//
//  CollapsedSidebarViewController.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit

class CollapsedSidebarViewController: SidebarController {
    override var type: SideBarType {
        .collapsed
    }
    
    override func setupView() {
        super.setupView()
        
        tableView.delegate   = self
        tableView.dataSource = self
        tableView.register(SidebarCell.self, forCellReuseIdentifier: SidebarCell.Identifier.collapsed)
        tableView.register(ProfileSideBarCell.self, forCellReuseIdentifier: ProfileSideBarCell.Identifier.collapsed)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: SideBarConst.topCellIdentifier)
    }
}

extension CollapsedSidebarViewController: UITableViewDataSource {
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
            cell = tableView.dequeueReusableCell(withIdentifier: ProfileSideBarCell.Identifier.collapsed,
                                                 for: indexPath)
        } else if indexPath.section == SideBarConst.baseSectionIndex    ||
           indexPath.section == SideBarConst.dynamicSectionIndex ||
           indexPath.section == SideBarConst.staticSectionIndex  {
            cell = tableView.dequeueReusableCell(withIdentifier: SidebarCell.Identifier.collapsed,
                                                 for: indexPath)
        } else {
            cell = tableView.dequeueReusableCell(withIdentifier: SideBarConst.topCellIdentifier,
                                                 for: indexPath)
        }

        if indexPath.section == SideBarConst.topSectionIndex {
            cell.selectionStyle   = .default
            cell.backgroundColor  = .clear
            cell.tintColor        = isDarkMode ? .white : .black
            cell.imageView?.image = UIImage(systemName: SideBarConst.topCellIconName)
        } else if indexPath.section == SideBarConst.baseSectionIndex {
            guard let item = dataProvider?.baseItems[indexPath.row] else {
                return cell
            }
            if indexPath.row == 0, let cell = cell as? ProfileSideBarCell {
                let border = isDarkMode ? CustomTabBarConst.darkBackgroundColor : CustomTabBarConst.lightBackgroundColor
                cell.updateCell(icon: item.icon, borderColor: item.isSelected ? border : .clear)
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

extension CollapsedSidebarViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == SideBarConst.topSectionIndex {
            delegate?.expandSidebar()
        } else if indexPath.section == SideBarConst.baseSectionIndex   ||
                  indexPath.section == SideBarConst.staticSectionIndex ||
                  indexPath.section == SideBarConst.dynamicSectionIndex {
            delegate?.onItemPick(indexPath: indexPath)
        }
    }
}
