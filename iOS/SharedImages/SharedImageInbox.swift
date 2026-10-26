import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Shared only by Capital Wizard and its share extension. No session is shared.
enum SharedImageInbox {
    static let group = "group.com.capital-wizard.shared-images"
    static let maxBytes = 10 * 1024 * 1024
    enum Failure: Error { case unavailable, invalidImage, full }

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

    static func save(files: [[String: String]], text: String) throws {
        guard (1...4).contains(files.count), try pending().count < 10 else { throw Failure.full }
        let id = UUID().uuidString.lowercased()
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "files": files, "text": String(text.prefix(4000))])
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
