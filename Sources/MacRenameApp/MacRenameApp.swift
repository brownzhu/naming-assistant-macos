import SwiftUI
import AppKit

@main
struct MacRenameApp: App {
    @Environment(\.openWindow) private var openWindow
    @State private var viewModel = AppViewModel()
    private let serviceProvider = ServiceProvider()

    init() {
        // SPM executables don't auto-activate as foreground apps,
        // so the window won't receive keyboard focus without this.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()

        // Register the Services-menu provider. The Info.plist NSServices
        // declaration tells macOS what to advertise; this tells macOS where
        // to dispatch the call when the user picks our menu item.
        NSApp.servicesProvider = serviceProvider
        NSUpdateDynamicServices()
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            MainView(viewModel: viewModel)
                .task {
                    serviceProvider.setFileHandler { urls in
                        openWindow(id: "main")
                        NSApp.activate(ignoringOtherApps: true)
                        viewModel.addFiles(urls: urls)
                    }
                }
                .onOpenURL { url in
                    if let files = URLSchemeHandler.parseURLScheme(url) {
                        viewModel.addFiles(urls: files)
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Quick Rename") {
                    NSApp.orderFrontStandardAboutPanel(options: aboutPanelOptions())
                }
                Divider()
                Button("Reset Quick Rename…") {
                    confirmReset()
                }
            }
            CommandGroup(after: .newItem) {
                Button("Open Files...") {
                    viewModel.openFilePanel()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .pasteboard) {
                Button("Select All") {
                    viewModel.items.forEach { $0.isSelected = true }
                }
                .keyboardShortcut("a", modifiers: .command)

                Button("Deselect All") {
                    viewModel.items.forEach { $0.isSelected = false }
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Divider()

                Button("Focus Search Field") {
                    NotificationCenter.default.post(name: .quickRenameFocusSearch, object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("Focus Replace Field") {
                    NotificationCenter.default.post(name: .quickRenameFocusReplace, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Swap Search and Replace") {
                    viewModel.swapSearchAndReplace()
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
            }
            CommandGroup(replacing: .help) {
                Button("Quick Rename Help") {
                    openWindow(id: "help")
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }

        Window("Quick Rename Help", id: "help") {
            HelpView()
        }
        .defaultSize(width: 780, height: 560)
    }

    /// Shows a destructive-style confirmation, then wipes all persisted
    /// settings (last terms, MRU history, toggle states). Files in the
    /// current window are not affected.
    private func confirmReset() {
        let alert = NSAlert()
        alert.messageText = "Reset Quick Rename?"
        alert.informativeText = "This clears your last search and replace terms, the recent-history menus, and toggle states. The files currently in the window are not affected."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            viewModel.resetAllSettings()
        }
    }

    private func aboutPanelOptions() -> [NSApplication.AboutPanelOptionKey: Any] {
        let credits = NSMutableAttributedString()
        let regular = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let bold = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        let center = NSMutableParagraphStyle()
        center.alignment = .center

        credits.append(NSAttributedString(
            string: "Designed by ",
            attributes: [.font: regular, .paragraphStyle: center,
                         .foregroundColor: NSColor.labelColor]
        ))
        credits.append(NSAttributedString(
            string: "Simon Craig",
            attributes: [.font: bold, .paragraphStyle: center,
                         .foregroundColor: NSColor.labelColor]
        ))
        credits.append(NSAttributedString(
            string: "\n\nCode written by ",
            attributes: [.font: regular, .paragraphStyle: center,
                         .foregroundColor: NSColor.labelColor]
        ))
        credits.append(NSAttributedString(
            string: "Claude",
            attributes: [.font: bold, .paragraphStyle: center,
                         .foregroundColor: NSColor.labelColor]
        ))
        credits.append(NSAttributedString(
            string: " (Anthropic Claude Opus 4.6)\n\nA macOS port of PowerToys PowerRename.",
            attributes: [.font: regular, .paragraphStyle: center,
                         .foregroundColor: NSColor.secondaryLabelColor]
        ))

        return [
            .applicationName: "Quick Rename",
            .credits: credits,
            .init(rawValue: "Copyright"): "© 2026 Simon Craig",
        ]
    }
}
