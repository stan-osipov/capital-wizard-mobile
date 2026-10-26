import UIKit
import Social
import UniformTypeIdentifiers

/// iOS does not support launching the containing app from a Share Extension.
/// Save to the App Group; the app opens a draft on its next foreground/launch.
final class ShareViewController: SLComposeServiceViewController {
    private var saving = false
    private var ukrainian: Bool { Locale.preferredLanguages.first?.hasPrefix("uk") == true }
    private func label(_ english: String, _ ukrainian: String) -> String { self.ukrainian ? ukrainian : english }
    private var providers: [NSItemProvider] {
        (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Capital Wizard"
        placeholder = label("Add a message for AI…", "Додайте повідомлення для ШІ…")
        navigationItem.rightBarButtonItem?.title = label("Save", "Зберегти")
    }

    override func isContentValid() -> Bool { !saving && (1...4).contains(providers.count) }

    override func configurationItems() -> [Any]! {
        let item = SLComposeSheetConfigurationItem()!
        item.title = label("AI chat", "Чат із ШІ")
        item.value = label("Open Capital Wizard after saving", "Після збереження відкрийте Capital Wizard")
        item.tapHandler = {}
        return [item]
    }

    override func didSelectPost() {
        guard !saving else { return }
        saving = true
        validateContent()
        let providers = providers
        let text = contentText ?? ""
        Task {
            do {
                var files: [[String: String]] = []
                for (index, provider) in providers.enumerated() {
                    let image: [String: String] = try await withCheckedThrowingContinuation { continuation in
                        provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                            guard let url else { continuation.resume(throwing: SharedImageInbox.Failure.invalidImage); return }
                            do { continuation.resume(returning: try SharedImageInbox.image(at: url, index: index)) }
                            catch { continuation.resume(throwing: error) }
                        }
                    }
                    // Keep the extension below its memory budget while serializing.
                    let encodedBytes = files.reduce(0) { $0 + ($1["base64"]?.utf8.count ?? 0) } + (image["base64"]?.utf8.count ?? 0)
                    guard encodedBytes <= ((SharedImageInbox.maxBytes + 2) / 3) * 4 else { throw SharedImageInbox.Failure.full }
                    files.append(image)
                }
                // JSON serialization and disk writes stay off the extension UI thread.
                try await Task.detached { try SharedImageInbox.save(files: files, text: text) }.value
                let alert = UIAlertController(title: label("Saved for AI chat", "Збережено для чату із ШІ"),
                    message: label("Open Capital Wizard to review the images and send your message.",
                                   "Відкрийте Capital Wizard, щоб переглянути зображення та надіслати повідомлення."), preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: label("Done", "Готово"), style: .default) { [weak self] _ in
                    self?.extensionContext?.completeRequest(returningItems: nil)
                })
                present(alert, animated: true)
            } catch {
                saving = false
                validateContent()
                let alert = UIAlertController(title: label("Could not save images", "Не вдалося зберегти зображення"),
                    message: label("Share up to 4 images totaling at most 10 MB. Open Capital Wizard to finish any pending imports, then try again.",
                                   "Можна додати до 4 зображень загальним розміром до 10 МБ. Відкрийте Capital Wizard, щоб завершити попередній імпорт, і спробуйте ще раз."), preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            }
        }
    }
}
