//
//  ApplicationCenterController.swift
//  capital-wizard-ios
//
//  Created by Roman on 07.02.2026.
//

import UIKit

protocol ApplicationCenterControllerDelegate: AnyObject {
    func onAppChosen(_ appData: Application)
}

class ApplicationCenterController: ApplicationViewController {

    var data: Array<Application> = []
    weak var delegate: ApplicationCenterControllerDelegate?

    var selectedApplications: Array<Application?> = [] {
        didSet {
            collectionView?.reloadData()
        }
    }

    private lazy var cellSize: CGSize = .zero
    private var searchResults: Array<Application> = []

    private var isSearching = false

    private func activeDataset() -> Array<Application> {
        if isSearching {
            return searchResults
        } else {
            return data
        }
    }

    private lazy var windowService: WindowsService? = ServiceManager.shared.getService()
    private lazy var authService:   AuthService?    = ServiceManager.shared.getService()

    var collectionView: UICollectionView?

    private var navigationBarLine: UIView?
    private var searchBar:         UISearchBar?
    private var profileButton:     RoundButton?

    private var colorScheme: ColorScheme?

    private var transitionPath: WindowTransitionPath?

    override func viewDidLoad() {
        super.viewDidLoad()

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical

        collectionView = UICollectionView(frame: view.frame, collectionViewLayout: layout)
        collectionView?.dataSource = self
        collectionView?.delegate   = self

        collectionView?.register(ApplicationCell.self, forCellWithReuseIdentifier: ApplicationCell.identifier)


        // (Roman) TODO: Remove hardcode
        let viewWidth = view.frame.width < view.frame.height ? view.frame.width : view.frame.height
        let cellforRow = UIDevice.current.userInterfaceIdiom == .pad ? 7.0 : 4.0
        let width      = viewWidth * 0.9 / cellforRow - 10
        cellSize       = CGSize(width: width, height: width)

        setupView()
        loadProfileImage()

        hideKeyboardWhenTappedAround()
    }

    private func setupView() {
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false

        guard let colorScheme = windowService?.colorScheme else  {
            return
        }
        let colors       = AppColors(scheme: colorScheme)
        self.colorScheme = colorScheme
        view.backgroundColor = colors.backgroundColor

        let someView = CustomTitleView()

        if let navBar = navigationController?.navigationBar {
            if navigationBarLine == nil {
                let lineView = UIView(frame: CGRect(x: 0, y: navBar.bounds.height - 1, width: navBar.bounds.width, height: 1))
                lineView.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
                navBar.addSubview(lineView)

                navigationBarLine = lineView
            }
            navigationBarLine?.backgroundColor = colors.separatorLine
        }

        navigationItem.titleView = someView

        someView.translatesAutoresizingMaskIntoConstraints = false

        let input = UISearchBar()
        someView.addSubview(input)

        self.searchBar = input
        input.layer.cornerRadius = 18
        input.placeholder   = "Search"
        input.clipsToBounds = true
        input.delegate = self

        let backgroundColor: UIColor = colorScheme.isDarkMode ? .black : .white

        input.backgroundColor = backgroundColor
        input.searchBarStyle  = .minimal
        input.barStyle = colorScheme.isDarkMode ? .black : .default
        input.searchTextField.textColor = colorScheme.isDarkMode ? .white : .black

        input.translatesAutoresizingMaskIntoConstraints = false

        input.leadingAnchor.constraint(equalTo: someView.safeAreaLayoutGuide.leadingAnchor).isActive = true
        input.heightAnchor.constraint(equalTo: someView.heightAnchor, multiplier: 0.8).isActive = true
        input.centerYAnchor.constraint(equalTo: someView.safeAreaLayoutGuide.centerYAnchor).isActive = true
        input.widthAnchor.constraint(equalTo: someView.widthAnchor, multiplier: 0.65).isActive = true

        // Profile
        let profileButton = RoundButton(type: .custom)

        profileButton.configuration?.cornerStyle = .dynamic
        profileButton.imageView?.contentMode = .scaleAspectFill
        profileButton.contentVerticalAlignment = .fill
        profileButton.contentHorizontalAlignment = .fill

        // (Roman) TODO: Remove hardocde
        profileButton.layer.borderColor = UIColor(red: 49/255, green: 186/255, blue: 174/255, alpha: 1).cgColor
        profileButton.layer.borderWidth = 2

        profileButton.imageView?.clipsToBounds = true

        profileButton.addTarget(self, action: #selector(profileClickHandler), for: .touchUpInside)

        profileButton.translatesAutoresizingMaskIntoConstraints = false;

        someView.addSubview(profileButton)

        NSLayoutConstraint.activate([
            profileButton.trailingAnchor.constraint(equalTo: someView.safeAreaLayoutGuide.trailingAnchor),
            profileButton.centerYAnchor.constraint(equalTo: someView.centerYAnchor),
            profileButton.heightAnchor.constraint(equalTo: someView.safeAreaLayoutGuide.heightAnchor, multiplier: 0.8),
            profileButton.widthAnchor.constraint(equalTo: profileButton.heightAnchor),
        ])
        profileButton.imageView?.layer.cornerRadius = profileButton.frame.height/2

        self.profileButton = profileButton

        guard let collectionView = collectionView else {
            return
        }

        self.view.addSubview(collectionView)

        self.collectionView?.backgroundColor = .clear

        self.collectionView?.translatesAutoresizingMaskIntoConstraints = false
        self.collectionView?.widthAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.widthAnchor, multiplier: 0.9).isActive = true
        self.collectionView?.centerXAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.centerXAnchor).isActive = true
        self.collectionView?.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 30).isActive = true
        self.collectionView?.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor).isActive = true
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
                self.profileButton?.setImage(image, for: .normal)
                let radius = (self.profileButton?.frame.height ?? 0) / 2
                self.profileButton?.imageView?.layer.cornerRadius = radius
            }
        }
    }

    func onColorSchemeChanged(_ scheme: ColorScheme) {
        let colors = AppColors(scheme: scheme)

        if scheme.isDarkMode {
            view.backgroundColor = .black

            searchBar?.barStyle        = .black
            searchBar?.backgroundColor = .black

            searchBar?.searchTextField.textColor = .white
        } else {
            view.backgroundColor = .white

            searchBar?.barStyle        = .default
            searchBar?.backgroundColor = .white

            searchBar?.searchTextField.textColor = .black
        }
        colorScheme = scheme

        navigationBarLine?.backgroundColor = colors.separatorLine

        if self.isViewLoaded {
            self.collectionView?.reloadData()
        }
    }
    
    @objc private func profileClickHandler(_ sender: Any) {
        guard let button = sender as? UIButton else { return }

        let vc = ProfilePopoverController(colorScheme: colorScheme ?? .dark)

        if UIDevice.current.userInterfaceIdiom == .phone {
            vc.modalPresentationStyle = .pageSheet
            if let sheet = vc.sheetPresentationController {
                sheet.detents = [.medium()]
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = 30
            }
            self.present(vc, animated: true)
        } else {
            vc.preferredContentSize = CGSize(width: 280, height: 260)
            windowService?.presentPopover(vc, with: button.bounds, direction: .up, sourceView: button)
        }
    }
}

extension ApplicationCenterController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchText.isEmpty {
            searchResults = data
        } else {
            searchResults = data.filter { $0.name.range(of: searchText, options: .caseInsensitive) != nil }
        }

        isSearching = true

        collectionView?.reloadData()
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
        searchBar.text = ""
        searchResults.removeAll()
        isSearching = false
        collectionView?.reloadData()
    }

    private func hideKeyboardWhenTappedAround() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.delegate = self
        view.addGestureRecognizer(tap)
    }

    @objc private func dismissKeyboard() {
        guard let searchBar = searchBar, searchBar.isFirstResponder else {
            return
        }
        searchBar.resignFirstResponder()
    }
}

extension ApplicationCenterController {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let searchBar = self.searchBar else {
            return true
        }

        if touch.view?.isDescendant(of: searchBar) == true {
            return false
        }

        return true
    }
}

extension ApplicationCenterController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        activeDataset().count
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        1
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ApplicationCell.identifier, for: indexPath) as! ApplicationCell

        let data = activeDataset()
        let application = data[indexPath.row]
        let isDarkMode = colorScheme?.isDarkMode ?? false
        let color: UIColor = isDarkMode ? .white : .black

        let isSelected = selectedApplications.first(where: { $0?.id == application.id } ) != nil

        if isSelected {
            let bgColor = isDarkMode ? CustomTabBarConst.darkBackgroundColor : CustomTabBarConst.lightBackgroundColor
            cell.setupCell(image: application.bigIcon,
                           name: application.name,
                           id: indexPath.row,
                           delegate: self,
                           withColor: color,
                           backgoundColor: bgColor,
                           imageColor: .white)
        } else {
            cell.setupCell(image: application.bigIcon,
                           name: application.name,
                           id: indexPath.row,
                           delegate: self,
                           withColor: color,
                           imageColor: color)
        }

        return cell
    }
}

extension ApplicationCenterController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return cellSize
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return 2
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return 2
    }
}

extension ApplicationCenterController: ApplicationCellDelegate {
    func onTapOnCell(_ cell: ApplicationCell) {
        let data = activeDataset()

        guard cell.id < data.count else {
            return
        }

        let appData = data[cell.id]

        delegate?.onAppChosen(appData)
    }
}
