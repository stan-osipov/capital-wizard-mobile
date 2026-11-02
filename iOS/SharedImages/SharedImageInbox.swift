import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Shared only by Capital Wizard and its share extension. No session is shared.
///
/// Carries BOTH kinds of share, which is why `kind` is on the payload:
///
///   .images    — up to 4 pictures, from the share extension. Opens an AI chat draft.
///   .statement — one document, from the app's own document types (see
///                `Info.plist` → `CFBundleDocumentTypes` and `SceneDelegate`).
///                Opens the import wizard.
///
/// The type name, the app-group id and the folder all still say "images"
/// because the group is provisioned under that name and cannot be renamed
/// without breaking the handoff for everybody mid-upgrade.
enum SharedImageInbox {
    static let group = "group.com.capital-wizard.shared-images"
    static let maxBytes = 10 * 1024 * 1024
    enum Failure: Error { case unavailable, invalidImage, invalidDocument, full }

    /// Which destination the web app routes a payload to. Written into the JSON
    /// and read by `nativeSharedStatement.ts`; an absent value there means
    /// `.images`, which is what builds before documents existed wrote.
    enum Kind: String { case images, statement }

    /// Posted after a file the APP itself received lands in the inbox, so a
    /// WebView that is already up delivers it now instead of at the next
    /// foreground. The extension never posts it — it does not share a process
    /// with the app.
    static let didReceive = Notification.Name("SharedImageInboxDidReceive")

    private static func directory() throws -> URL {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { throw Failure.unavailable }
        let folder = root.appendingPathComponent("shared-images", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var protected = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protected.setResourceValues(values)
        return folder
    }

    static func pending() throws -> [URL] {
        let files = try FileManager.default.contentsOfDirectory(at: directory(), includingPropertiesForKeys: [.creationDateKey])
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        return files.filter { url in
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            if created < cutoff { try? FileManager.default.removeItem(at: url); return false }
            return url.pathExtension == "json"
        }.sorted { a, b in
            ((try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
                < ((try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
        }
    }

    /// Read the provider's temporary URL INSIDE its completion callback.
    static func image(at url: URL, index: Int) throws -> [String: String] {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= maxBytes,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              (properties[kCGImagePropertyPixelWidth] as? Int ?? 0) > 0,
              (properties[kCGImagePropertyPixelHeight] as? Int ?? 0) > 0 else { throw Failure.invalidImage }
        let originalType = type as String
        var data: Data
        var mime: String
        var ext: String
        if originalType == UTType.png.identifier || originalType == UTType.jpeg.identifier || originalType == UTType.gif.identifier {
            data = try Data(contentsOf: url)
            mime = originalType == UTType.png.identifier ? "image/png" : originalType == UTType.gif.identifier ? "image/gif" : "image/jpeg"
            ext = originalType == UTType.png.identifier ? "png" : originalType == UTType.gif.identifier ? "gif" : "jpg"
        } else {
            // Camera HEIC becomes an oriented, bounded JPEG accepted by the AI.
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2560]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw Failure.invalidImage }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw Failure.invalidImage }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw Failure.invalidImage }
            data = output as Data
            mime = "image/jpeg"
            ext = "jpg"
        }
        guard !data.isEmpty, data.count <= maxBytes else { throw Failure.invalidImage }
        return ["name": "shared-image-\(index + 1).\(ext)", "mime": mime, "base64": data.base64EncodedString()]
    }

    /// A statement, carried through as the bytes the user shared.
    ///
    /// Nothing here judges whether the format is importable: the share sheet is
    /// not the place to refuse a `.numbers` export, and the institution picker
    /// (which the user is about to see) is what finally decides. The only limits
    /// are the ones the transport imposes — the payload crosses into the WebView
    /// as base64 inside an `evaluateJavaScript` string.
    ///
    /// Read the provider's URL INSIDE its callback / access scope, as with `image(at:)`.
    static func document(at url: URL) throws -> [String: String] {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= maxBytes else { throw Failure.invalidDocument }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty, data.count <= maxBytes else { throw Failure.invalidDocument }
        // `lastPathComponent` is already a basename, but a provider can hand over
        // a name that is empty or absurdly long, and the web side reads this for
        // the extension it routes on.
        let component = url.lastPathComponent
        let name = component.isEmpty || component == "." || component == ".."
            ? "statement" : String(component.prefix(200))
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return ["name": name, "mime": mime, "base64": data.base64EncodedString()]
    }

    /// Which route a file the OS handed us takes.
    ///
    /// An image goes to the AI chat draft wherever it came in from. The app
    /// declares no image document type, so this cannot happen via our own
    /// `Info.plist`; answering it anyway means a picture that reaches the app by
    /// some other door behaves the way every other shared picture does, rather
    /// than opening an import wizard that cannot read it.
    static func kind(forFileAt url: URL) -> Kind {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return .statement }
        return type.conforms(to: .image) ? .images : .statement
    }

    /// A file the OS handed the APP — the share sheet's "Capital Wizard", or
    /// "Open in". Returns the kind it was filed as, so the caller can say what
    /// happened.
    @discardableResult
    static func save(fileAt url: URL) throws -> Kind {
        let kind = kind(forFileAt: url)
        let file = kind == .images ? try image(at: url, index: 0) : try document(at: url)
        try save(files: [file], text: "", kind: kind)
        return kind
    }

    static func save(files: [[String: String]], text: String, kind: Kind = .images) throws {
        // One statement, because the wizard parses one — importing part of a
        // batch would be worse than refusing it. Pictures still come in fours.
        let allowed = kind == .statement ? 1...1 : 1...4
        guard allowed.contains(files.count), try pending().count < 10 else { throw Failure.full }
        let id = UUID().uuidString.lowercased()
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "kind": kind.rawValue, "files": files, "text": String(text.prefix(4000))])
        try data.write(to: directory().appendingPathComponent("\(id).json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func next() throws -> String? {
        guard let url = try pending().first else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func acknowledge(_ id: String) throws {
        guard UUID(uuidString: id) != nil else { return }
        let file = try directory().appendingPathComponent("\(id.lowercased()).json")
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}
