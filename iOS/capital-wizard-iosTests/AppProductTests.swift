import Testing
import Foundation
@testable import capital_wizard_ios

struct AppProductTests {
    @Test func productsHaveSeparateHostsAndCallbacks() {
        #expect(AppProduct.codingLab.appHost == "app.coding-lab.co")
        #expect(AppProduct.codingLab.developmentHost == "dev.coding-lab.co")
        #expect(AppProduct.codingLab.urlScheme == "coding-lab-ios")
        #expect(AppProduct.capitalWizard.appHost == "app.capital-wizard.com")
        #expect(AppProduct.capitalWizard.urlScheme == "capital-wizard-ios")
        #expect(!AppProduct.codingLab.supportsStoreBilling)
        #expect(AppProduct.capitalWizard.supportsStoreBilling)
    }

    @Test func capitalWizardDoesNotClaimCodingLabLinks() {
        for value in ["https://app.coding-lab.co/ai-project", "coding-lab-ios://open?path=/worker"] {
            #expect(DeepLinkService.appPath(from: URL(string: value)!) == nil)
        }
    }
}
