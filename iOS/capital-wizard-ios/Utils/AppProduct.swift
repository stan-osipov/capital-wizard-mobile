import Foundation

/// Build-time identity. A page or persisted preference cannot change products.
/// Both iOS targets share the shell; Android mirrors this with product flavors.
enum AppProduct: String, CaseIterable {
    case capitalWizard = "capital-wizard"
    case codingLab = "coding-lab"

    #if CODING_LAB
    static let current = AppProduct.codingLab
    #else
    static let current = AppProduct.capitalWizard
    #endif

    var name: String { self == .codingLab ? "Coding Lab" : "Capital Wizard" }
    var siteHost: String { self == .codingLab ? "coding-lab.co" : "capital-wizard.com" }
    var appHost: String { "app.\(siteHost)" }
    var developmentHost: String { "dev.\(siteHost)" }
    var urlScheme: String { "\(rawValue)-ios" }
    // Legal pages are part of the shared app and resolve the product by host.
    var legalOrigin: String { self == .codingLab ? "https://\(appHost)" : "https://\(siteHost)" }
    var supportsStoreBilling: Bool { self == .capitalWizard }
}
