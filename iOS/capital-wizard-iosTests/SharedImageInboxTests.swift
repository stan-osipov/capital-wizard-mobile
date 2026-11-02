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

/// The statement half of the inbox — a document shared in via the app's own
/// `CFBundleDocumentTypes` rather than through the share extension.
struct SharedStatementInboxTests {
    private func temporaryFile(_ name: String, _ bytes: Data) throws -> URL {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: file)
        return file
    }

    @Test func carriesTheStatementBytesAndDerivesItsTypeFromTheExtension() throws {
        let bytes = Data("date;amount\n2026-01-02;-12.50\n".utf8)
        let file = try temporaryFile("statement.csv", bytes)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let document = try SharedImageInbox.document(at: file)
        #expect(document["name"] == "statement.csv")
        #expect(document["mime"] == "text/csv")
        #expect(Data(base64Encoded: document["base64"]!) == bytes)
    }

    @Test func acceptsAFormatNoParserDeclares() throws {
        // The share sheet is not the place to refuse a file: the institution
        // picker the user is about to see is what judges it. Refusing here would
        // leave them staring at a share that did nothing.
        let file = try temporaryFile("export.numbers", Data("anything".utf8))
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        #expect(try SharedImageInbox.document(at: file)["name"] == "export.numbers")
    }

    @Test func fallsBackToANeutralTypeForAnUnknownExtension() throws {
        let file = try temporaryFile("statement.wat", Data("anything".utf8))
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        #expect(try SharedImageInbox.document(at: file)["mime"] == "application/octet-stream")
    }

    @Test func refusesEmptyAndOversizedDocuments() throws {
        let empty = try temporaryFile("empty.pdf", Data())
        defer { try? FileManager.default.removeItem(at: empty.deletingLastPathComponent()) }
        #expect(throws: (any Error).self) { try SharedImageInbox.document(at: empty) }

        let huge = try temporaryFile("huge.pdf", Data(repeating: 0, count: SharedImageInbox.maxBytes + 1))
        defer { try? FileManager.default.removeItem(at: huge.deletingLastPathComponent()) }
        #expect(throws: (any Error).self) { try SharedImageInbox.document(at: huge) }
    }

    /// Pictures keep the AI-chat route whatever door they arrive through;
    /// everything else is a statement and opens the wizard.
    @Test func routesPicturesToTheChatDraftAndDocumentsToTheWizard() {
        let url = { (name: String) in URL(fileURLWithPath: "/tmp/\(name)") }
        #expect(SharedImageInbox.kind(forFileAt: url("receipt.png")) == .images)
        #expect(SharedImageInbox.kind(forFileAt: url("receipt.HEIC")) == .images)
        #expect(SharedImageInbox.kind(forFileAt: url("statement.pdf")) == .statement)
        #expect(SharedImageInbox.kind(forFileAt: url("statement.xlsx")) == .statement)
        #expect(SharedImageInbox.kind(forFileAt: url("statement.csv")) == .statement)
        // No extension to go on: a statement, because that is the only route a
        // file reaches the app by (the extension owns the picture route).
        #expect(SharedImageInbox.kind(forFileAt: url("statement")) == .statement)
    }
}
