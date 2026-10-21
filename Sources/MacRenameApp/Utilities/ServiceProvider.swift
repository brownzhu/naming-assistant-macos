import AppKit

/// Handles the "Rename with Quick Rename" Services-menu invocation.
/// macOS surfaces this in Finder's right-click menu (under Services on
/// most files; promoted to the main menu after first use on macOS 14+).
@MainActor
final class ServiceProvider: NSObject {
    // Services can arrive before SwiftUI has attached its views. Keep the
    // requests until a window can handle them instead of posting a transient
    // notification that would lose the cold-launch selection.
    private var pendingFileRequests: [[URL]] = []
    private var fileHandler: (([URL]) -> Void)?

    func setFileHandler(_ handler: @escaping ([URL]) -> Void) {
        fileHandler = handler
        deliverPendingFiles()
    }

    /// Selector form: <NSMessage>:userData:error:
    /// Declared in Info.plist NSServices ▸ NSMessage = "renameFiles".
    @objc func renameFiles(
        _ pboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        let modernURLs = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        let legacyPaths = pboard.propertyList(
            forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")
        ) as? [String] ?? []
        let urls = (modernURLs.isEmpty ? legacyPaths.map { URL(fileURLWithPath: $0) } : modernURLs)
            .filter(\.isFileURL)
        guard !urls.isEmpty else {
            return
        }
        pendingFileRequests.append(urls)
        NSApp.activate(ignoringOtherApps: true)
        deliverPendingFiles()
    }

    private func deliverPendingFiles() {
        guard let fileHandler, !pendingFileRequests.isEmpty else { return }
        let requests = pendingFileRequests
        pendingFileRequests.removeAll()
        for urls in requests {
            fileHandler(urls)
        }
    }
}

extension Notification.Name {
    /// Posted by the "Focus Search Field" command (⌘L) — handled by
    /// `SearchReplaceBar` to move keyboard focus into the search field.
    static let quickRenameFocusSearch = Notification.Name("QuickRenameFocusSearch")
    /// Posted by the "Focus Replace Field" command (⌘⇧L).
    static let quickRenameFocusReplace = Notification.Name("QuickRenameFocusReplace")
}
