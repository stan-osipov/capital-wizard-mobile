//
//  SidebarController.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit

struct SideBarConst {
    static let expandedWidth: CGFloat  = 250
    static let collapsedWidth: CGFloat = 55
    static let rowHeight: CGFloat      = 55
    static let sectionsAmout           = 4
    static let topSectionIndex         = 0
    static let baseSectionIndex        = 1
    static let staticSectionIndex      = 2
    static let dynamicSectionIndex     = 3
    
    static let topSectionRowsInSection = 1
    static let topCellIdentifier       = "Sidebar"
    static let topCellIconName         = "sidebar.left"
    
    static let cellBackgroundColor    = UIColor.lightGray.withAlphaComponent(0.2)
}

protocol SideBarDataProvider: AnyObject {
    var baseItems:    Array<BarItem> { get }
    var staticItems:  Array<BarItem> { get }
    var dynamicItems: Array<BarItem> { get }
}

protocol SideBarDelegate: AnyObject {
    func onItemPick(indexPath: IndexPath)
    func onCloseClicked(for indexPath: IndexPath)
    func expandSidebar()
    func collapseSidebar()
}

enum SideBarType {
    case collapsed
    case expanded
}

class SidebarController: UIViewController {
    var tableView: UITableView = UITableView()
    
    weak var dataProvider: SideBarDataProvider?
    weak var delegate:     SideBarDelegate?
    
    private lazy var windowsService: WindowsService? = ServiceManager.shared.getService()
    
    var type: SideBarType {
        .collapsed
    }
    
    var colorScheme: ColorScheme {
        windowsService?.colorScheme ?? .light
    }

    var isDarkMode: Bool {
        return windowsService?.colorScheme.isDarkMode ?? false
    }
    
    func reloadAt(_ indexPaths: Array<IndexPath>) {
        tableView.reloadRows(at: indexPaths, with: .automatic)
    }
    
    func update(callback: () -> Void) {
        tableView.performBatchUpdates {
            callback()
        }
    }
    
    func add(at indexPaths: Array<IndexPath>) {
        tableView.insertRows(at: indexPaths, with: .automatic)
    }
    
    func deleate(at indexPaths: Array<IndexPath>) {
        tableView.deleteRows(at: indexPaths, with: .automatic)
    }
    
    func reload() {
        tableView.reloadData()
    }
    
    func onSwiched() {
        reload()
        let colors = AppColors(scheme: colorScheme)
        view.backgroundColor = colors.backgroundColor
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupView()
    }
    
    func setupView() {
        let colors = AppColors(scheme: colorScheme)
        view.backgroundColor = colors.backgroundColor
        navigationController?.setNavigationBarHidden(true, animated: false)

        tableView.frame            = view.bounds
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.separatorStyle   = .none
        tableView.backgroundColor  = .clear
        tableView.rowHeight        = SideBarConst.rowHeight
        
        view.addSubview(tableView)
    }
    
    func updateColorScheme(_ scheme: ColorScheme) {
        reload()
        let colors = AppColors(scheme: scheme)
        view.backgroundColor = colors.backgroundColor
    }
        
    func updateCell(_ cell: SidebarCell, with item: BarItem) {
        var tintColor: UIColor = isDarkMode ? .white : .black
        var bgColor:   UIColor = SideBarConst.cellBackgroundColor

        if item.isSelected {
            tintColor = .white
            bgColor   = isDarkMode ? CustomTabBarConst.darkBackgroundColor : CustomTabBarConst.lightBackgroundColor
        }
        
        if type == .collapsed {
            cell.updateCell(icon: item.icon, tintColor: tintColor, backgroundColor: bgColor, badge: item.badge)
        } else if type == .expanded {
            cell.updateCell(icon: item.icon, tintColor: tintColor, backgroundColor: bgColor, title: item.name, badge: item.badge)
        }
    }
}
