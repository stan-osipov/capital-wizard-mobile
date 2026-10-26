import Foundation
import ImageIO
import Testing
import UIKit
@testable import capital_wizard_ios

struct SharedImageInboxTests {
    @Test @MainActor func preservesScreenshotBytesAndNames() throws {
        let data = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: file) }
        try data.write(to: file)
        let image = try SharedImageInbox.image(at: file, index: 1)
        #expect(image["name"] == "shared-image-2.png")
        #expect(image["mime"] == "image/png")
        #expect(Data(base64Encoded: image["base64"]!) == data)
    }

    @Test func rejectsTextDisguisedAsAnImage() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("not an image".utf8).write(to: file)
        #expect(throws: (any Error).self) { try SharedImageInbox.image(at: file, index: 0) }
    }

    @Test func rejectsOversizedProviderFilesBeforeDecoding() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(repeating: 0, count: SharedImageInbox.maxBytes + 1).write(to: file)
        #expect(throws: (any Error).self) { try SharedImageInbox.image(at: file, index: 0) }
    }
}
