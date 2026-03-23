//
//  SplitViewController.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit

protocol ApplicationNavigation: AnyObject {
    func onProfileClicked()
    func updateBackground(loading id: String?, removed removedId: String?)
    func onLayoutChanged(to layout: ViewUILayout, deSelected: Array<String>, isUserInitiated: Bool)
    func onClose(item: BarItem, layout: ViewUILayout)
    func animationControllerForTransition(fromVC: UIViewController,
                                          to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning?
}

class SplitViewController: UISplitViewController, UISplitViewControllerDelegate, SideBarDataProvider, NavigationContainer {
    var baseItems:    Array<BarItem> = []
    var staticItems:  Array<BarItem> = []
    var dynamicItems: Array<BarItem> = []
    
    private let collapsedSidebar = CollapsedSidebarViewController()
    private let expandedSidebar  = ExpandedSidebarViewController()
    
    private var expandedWidthConstraint: NSLayoutConstraint?
    
    private var layout: ViewUILayout = .none
    
    private var sidebar: SidebarController {
        isExpanded ? expandedSidebar : collapsedSidebar
    }
    
    private let container = SplitViewsContainer()
    
    private var isReady = false

    weak var colorSchemeDelegate: ColorSchemeDelegate?
    weak var dockingDelegate:     DockingDelegate?

    private var overlayView: UIView?
    
    private var isExpanded = false
    
    private lazy var windowService:      WindowsService? = ServiceManager.shared.getService()
    private lazy var authService:        AuthService?    = ServiceManager.shared.getService()
    private lazy var colorChangeHandler: EventCallback   = EventCallback(onColorSchemeChanged(_:))

    private var cachedProfileImage: UIImage?
    
    override init(style: UISplitViewController.Style) {
        super.init(style: style)
        delegate = self
        preferredPrimaryColumnWidthFraction = 0.12
        
        minimumPrimaryColumnWidth = SideBarConst.collapsedWidth
        maximumPrimaryColumnWidth = SideBarConst.collapsedWidth
        
        preferredDisplayMode   = .oneBesideSecondary
        preferredSplitBehavior = .tile
        presentsWithGesture    = false
        
        collapsedSidebar.delegate     = self
        collapsedSidebar.dataProvider = self
        expandedSidebar.delegate      = self
        expandedSidebar.dataProvider  = self
        
        setViewController(collapsedSidebar, for: .primary)
        setViewController(container, for: .secondary)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        isReady = true
        expandSidebar()
        loadProfileImage()
    }

    private func loadProfileImage() {
        Task {
            guard let user = authService?.client.currentUser,
                  let avatarJson = user.userMetadata["avatar_url"],
                  case .string(let urlString) = avatarJson,
                  let url = URL(string: urlString) else { return }

            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else { return }

            await MainActor.run {
                self.cachedProfileImage = image
                self.applyProfileImage()
            }
        }
    }

    private func applyProfileImage() {
        guard !baseItems.isEmpty, let image = cachedProfileImage else { return }
        baseItems[0].icon = image
        guard isViewLoaded else { return }
        let profilePath = IndexPath(row: 0, section: SideBarConst.baseSectionIndex)
        sidebar.reloadAt([profilePath])
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        windowService?.onColorSchemeChanged += colorChangeHandler
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        windowService?.onColorSchemeChanged -= colorChangeHandler
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if #available(iOS 13.0, *) {
            if self.traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
                colorSchemeDelegate?.onColorThemeChanged(to: traitCollection.userInterfaceStyle)
            }
        } else {
            // Fallback on earlier versions
        }
    }
    
    func add(application: Application) {
        guard let vc = application.rootController else {
            return
        }

        guard itemFor(id: application.id, priority: application.sideBarPriority) == nil else {
            return
        }

        let item = BarItem(id: application.id,
                               name: application.name,
                               icon: application.bigIcon,
                               vc: vc,
                               layout: application.layout)


        var section: Int
        var index:   Int

        var isFirstBaseItem = false

        if application.sideBarPriority == .baseApplication {
            index = baseItems.count
            baseItems.append(item)
            section = SideBarConst.baseSectionIndex
            if index == 0 { isFirstBaseItem = true }
        } else if application.sideBarPriority == .staticApplication {
            index = staticItems.count
            staticItems.append(item)
            section = SideBarConst.staticSectionIndex
        } else {
            index = dynamicItems.count
            dynamicItems.append(item)
            section = SideBarConst.dynamicSectionIndex
        }

        guard isReady else {
            return
        }
        sidebar.update {
            sidebar.add(at: [IndexPath(row: index, section: section)])
        }

        if isFirstBaseItem {
            applyProfileImage()
            loadProfileImage()
        }
    }
    
    func update(application: Application) {
        guard let indexPath = updateItem(application: application) else {
            return
        }

        sidebar.reloadAt([indexPath])
    }

    func remove(application: Application) {
        guard let item = itemFor(id: application.id, priority: application.sideBarPriority) else {
            return
        }
        guard let indexPath = indexPathFor(item: item) else {
            return
        }

        removeItemWith(id: application.id, priority: application.sideBarPriority)
        
        sidebar.update {
            sidebar.deleate(at: [indexPath])
        }
        
        if layout.controllers.contains(item.vc) {
            guard removeFromLayout(item: item) else {
                return
            }
            dockingDelegate?.onLayoutChanged(to: layout, deSelected: [item.id])
        }
    }
    
    func removeAll() {
        baseItems.removeAll()
        staticItems.removeAll()
        dynamicItems.removeAll()
        
        sidebar.reload()
        container.cleanUp()
    }
    

    func show(application: Application, with layout: ApplicationUILayout?) {
        guard let item = itemFor(id: application.id, priority: application.sideBarPriority) else {
            return
        }
        
        guard let indexPath = select(item: item) else {
            return
        }
        
        var indexForReload: Array<IndexPath> = addToLayout(item: item, prefered: layout)
        let deSelected = deSectedItemsFrom(indexForReload).map( { $0.id } )
        
        indexForReload.append(indexPath)
        
        sidebar.reloadAt(indexForReload)
        
        dockingDelegate?.onLayoutChanged(to: self.layout, deSelected: deSelected)
    }
    
    func hide(application: Application) {
        guard let item = itemFor(id: application.id, priority: application.sideBarPriority) else {
            return
        }
        
        dockingDelegate?.onClose(item: item, layout: layout)
    }
    
    func update(badge: Int, for application: Application) {
        guard let indexPath = updateItem(application: application, badge: badge) else {
            return
        }
        
        sidebar.reloadAt([indexPath])
    }
    
    private func deSectedItemsFrom(_ indexPaths: Array<IndexPath>) -> Array<BarItem> {
        var deSectedItems: Array<BarItem> = []
        indexPaths.forEach { indexPath in
            guard let item = itemFrom(indexPath: indexPath) else {
                return
            }
            deSectedItems.append(item)
        }
        return deSectedItems
    }
    
    private func addToLayout(item: BarItem, prefered: ApplicationUILayout?) -> Array<IndexPath> {
        guard let prefered = prefered else {
            return []
        }
        
        var itemsToRemove: Array<BarItem?> = []
        
        switch prefered {
        case .all:
            itemsToRemove.append(layout.trySetAnySplit(item: item))
        case .left:
            itemsToRemove.append(layout.trySetSplitLeft(item: item))
        case .right:
            itemsToRemove.append(layout.trySetSplitRight(item: item))
        case .wide:
            itemsToRemove.append(contentsOf: layout.trySetWide(item: item))
        default:
            itemsToRemove.append(layout.trySetSplitLeft(item: item))
        }
        
        var indexForReload: Array<IndexPath> = []
        itemsToRemove.forEach { item in
            if let indexPath = deSelect(item: item) {
                indexForReload.append(indexPath)
            }
        }
        container.setViewControllers(layout.controllers, animated: true)
        
        return indexForReload
    }
    
    private func removeFromLayout(item: BarItem) -> Bool {
        switch layout {
        case .split(let left, let right):
            guard layout.controllers.count == 2 else {
                return false
            }
            
            if let left = left, item.id == left.id {
                guard let right = right, right.layout.contains(.wide) else  {
                    return false
                }
                layout = .wide(right)
            }
            if let right = right, item.id == right.id {
                guard let left = left, left.layout.contains(.wide) else {
                    return false
                }
                layout = .wide(left)
            }
        case .wide(_), .none:
            return false
        }
        
        container.setViewControllers(layout.controllers, animated: true)
        return true
    }
    
    private func onColorSchemeChanged(_ scheme: ColorScheme) {
        sidebar.updateColorScheme(scheme)
    }
}

extension SplitViewController {
    private func itemFor(id: String, priority: Priority) -> BarItem? {
        switch priority {
        case .baseApplication:
            baseItems.first { $0.id == id }
        case .staticApplication:
            staticItems.first { $0.id == id }
        case .dynamicApplication:
            dynamicItems.first { $0.id == id }
        }
    }
    
    private func updateItem(application: Application, badge: Int = 0) -> IndexPath? {
        switch application.sideBarPriority {
        case .baseApplication:
            guard let index = baseItems.firstIndex(where: { $0.id == application.id }) else {
                return nil
            }
            baseItems[index].icon  = application.bigIcon
            baseItems[index].name  = application.name
            baseItems[index].badge = badge
            return IndexPath(row: index, section: SideBarConst.baseSectionIndex)
        case .staticApplication:
            guard let index = staticItems.firstIndex(where: { $0.id == application.id }) else {
                return nil
            }
            staticItems[index].icon  = application.bigIcon
            staticItems[index].name  = application.name
            staticItems[index].badge = badge
            return IndexPath(row: index, section: SideBarConst.staticSectionIndex)
        case .dynamicApplication:
            guard let index = dynamicItems.firstIndex(where: { $0.id == application.id }) else {
                return nil
            }
            dynamicItems[index].icon  = application.bigIcon
            dynamicItems[index].name  = application.name
            dynamicItems[index].badge = badge
            return IndexPath(row: index, section: SideBarConst.dynamicSectionIndex)
        }
    }
    
    private func itemFrom(indexPath: IndexPath) -> BarItem? {
        if indexPath.section == SideBarConst.baseSectionIndex {
            guard baseItems.count > indexPath.row else {
                return nil
            }
            return baseItems[indexPath.row]
        } else if indexPath.section == SideBarConst.staticSectionIndex {
            guard staticItems.count > indexPath.row else {
                return nil
            }
            return staticItems[indexPath.row]
        } else if indexPath.section == SideBarConst.dynamicSectionIndex {
            guard dynamicItems.count > indexPath.row else {
                return nil
            }
            return dynamicItems[indexPath.row]
        }
        return nil
    }
    
    @discardableResult private func removeItemWith(id: String, priority: Priority) -> BarItem? {
        switch priority {
        case .baseApplication:
            guard let index = baseItems.firstIndex(where: { $0.id == id }) else {
                return nil
            }
            return baseItems.remove(at: index)
        case .staticApplication:
            guard let index = staticItems.firstIndex(where: { $0.id == id }) else {
                return nil
            }
            return staticItems.remove(at: index)
        case .dynamicApplication:
            guard let index = dynamicItems.firstIndex(where: { $0.id == id }) else {
                return nil
            }
            return dynamicItems.remove(at: index)
        }
    }
    
    private func indexPathFor(item: BarItem) -> IndexPath? {
        if let index = baseItems.firstIndex(where: { $0.id == item.id}) {
            return IndexPath(row: index, section: SideBarConst.baseSectionIndex)
        } else if let index = staticItems.firstIndex(where: { $0.id == item.id }) {
            return IndexPath(row: index, section: SideBarConst.staticSectionIndex)
        } else if let index = dynamicItems.firstIndex(where: { $0.id == item.id }) {
            return IndexPath(row: index, section: SideBarConst.dynamicSectionIndex)
        }
        return nil
    }
    
    @discardableResult private func select(item: BarItem?) -> IndexPath? {
        guard let item = item else {
            return nil
        }
        if let index = baseItems.firstIndex(where: { $0.id == item.id }) {
            baseItems[index].isSelected = true
            return IndexPath(row: index, section: SideBarConst.baseSectionIndex)
        } else if let index = staticItems.firstIndex(where: { $0.id == item.id }) {
            staticItems[index].isSelected = true
            return IndexPath(row: index, section: SideBarConst.staticSectionIndex)
        } else if let index = dynamicItems.firstIndex(where: { $0.id == item.id }) {
            dynamicItems[index].isSelected = true
            return IndexPath(row: index, section: SideBarConst.dynamicSectionIndex)
        }
        return nil
    }
    
    @discardableResult private func deSelect(item: BarItem?) -> IndexPath? {
        guard let item = item else {
            return nil
        }
        if let index = baseItems.firstIndex(where: { $0.id == item.id }) {
            baseItems[index].isSelected = false
            return IndexPath(row: index, section: SideBarConst.baseSectionIndex)
        } else if let index = staticItems.firstIndex(where: { $0.id == item.id }) {
            staticItems[index].isSelected = false
            return IndexPath(row: index, section: SideBarConst.staticSectionIndex)
        } else if let index = dynamicItems.firstIndex(where: { $0.id == item.id }) {
            dynamicItems[index].isSelected = false
            return IndexPath(row: index, section: SideBarConst.dynamicSectionIndex)
        }
        return nil
    }
}

extension SplitViewController: SideBarDelegate {
    func onItemPick(indexPath: IndexPath) {
        guard let item = itemFrom(indexPath: indexPath) else {
            return
        }
        var indexForReload: Array<IndexPath> = []
        var deSelected: Array<String> = []

        if item.isSelected {
            guard removeFromLayout(item: item) else {
                return
            }
            deSelect(item: item)
            indexForReload.append(indexPath)
            deSelected.append(item.id)
        } else {
            select(item: item)
            indexForReload.append(contentsOf: addToLayout(item: item, prefered: item.layout))
            deSelected.append(contentsOf: deSectedItemsFrom(indexForReload).map( { $0.id } ))
            
            indexForReload.append(indexPath)
        }
        
        dockingDelegate?.onLayoutChanged(to: layout, deSelected: deSelected)
        
        sidebar.reloadAt(indexForReload)
    }

    func onCloseClicked(for indexPath: IndexPath) {
        guard let item = itemFrom(indexPath: indexPath) else {
            return
        }
        
        dockingDelegate?.onClose(item: item, layout: layout)
    }
    
    func expandSidebar() {
        isExpanded = true

        addChild(expandedSidebar)
        expandedSidebar.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(expandedSidebar.view)
        expandedSidebar.didMove(toParent: self)

        let widthConstraint = expandedSidebar.view.widthAnchor.constraint(equalToConstant:collapsedSidebar.view.frame.width)
        self.expandedWidthConstraint = widthConstraint

        NSLayoutConstraint.activate([
            expandedSidebar.view.topAnchor.constraint(equalTo: view.topAnchor),
            expandedSidebar.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            expandedSidebar.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            widthConstraint
        ])

        let overlay = UIView()
        overlay.backgroundColor = .black.withAlphaComponent(0)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(overlay, belowSubview: expandedSidebar.view)
        self.overlayView = overlay

        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(collapseSidebar))
        overlay.addGestureRecognizer(tap)
        
        sidebar.onSwiched()

        self.view.layoutIfNeeded()
        widthConstraint.constant = SideBarConst.expandedWidth

        UIView.animate(withDuration: 0.3) {
            overlay.backgroundColor = .black.withAlphaComponent(0.2)
            self.view.layoutIfNeeded()
        }
    }
    
    @objc func collapseSidebar() {
        isExpanded = false

        guard let widthConstraint = expandedWidthConstraint else {
            return
        }

        widthConstraint.constant = SideBarConst.collapsedWidth

        UIView.animate(withDuration: 0.3, animations: {
            self.overlayView?.backgroundColor = UIColor.black.withAlphaComponent(0.0)
            self.view.layoutIfNeeded()
        }, completion: { _ in
            self.expandedSidebar.willMove(toParent: nil)
            self.expandedSidebar.view.removeFromSuperview()
            self.expandedSidebar.removeFromParent()

            self.overlayView?.removeFromSuperview()
            self.overlayView = nil

            self.expandedWidthConstraint?.isActive = false
            self.expandedWidthConstraint = nil

            self.sidebar.onSwiched()
        })
    }
}

extension SplitViewController: UIPopoverPresentationControllerDelegate {

    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return .popover
    }

    func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {

    }

    func popoverPresentationControllerShouldDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) -> Bool {
        return true
    }
}
