import AppKit
import MacRenameCore

/// The Services entry accepts file URLs only. It never interprets pasted text,
/// starts a shell, or recursively enumerates selected folders.
@MainActor
final class NamingAssistantDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NamingWindowController?
    private var settingsController: ShortcutSettingsWindowController?
    private let incomingStore = IncomingSelectionStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        makeMenus()
        NSApplication.shared.servicesProvider = self
        NSUpdateDynamicServices()
        showWindow(nil)
        receive(incomingStore.drain())
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(nil)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        receive(filenames.map { URL(fileURLWithPath: $0) })
        sender.reply(toOpenOrPrint: .success)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        receive(urls)
    }

    @objc func suggestNames(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        var urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if urls.isEmpty,
           let paths = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            urls = paths.map { URL(fileURLWithPath: $0) }
        }
        guard !urls.isEmpty else {
            error.pointee = "请先在 Finder 中选中文件或文件夹。" as NSString
            return
        }
        do {
            try incomingStore.save(urls)
            receive(incomingStore.drain())
        } catch let queueError {
            error.pointee = "无法接收本次选择：\(queueError.localizedDescription)" as NSString
        }
    }

    @objc func showWindow(_ sender: Any?) {
        if windowController == nil { windowController = NamingWindowController() }
        windowController?.showWindow(sender)
        windowController?.window?.makeKeyAndOrderFront(sender)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func addFiles(_ sender: Any?) {
        showWindow(sender)
        windowController?.chooseFiles(sender)
    }

    @objc func showSettings(_ sender: Any?) {
        if settingsController == nil { settingsController = ShortcutSettingsWindowController() }
        settingsController?.showWindow(sender)
        settingsController?.window?.makeKeyAndOrderFront(sender)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func receive(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        showWindow(nil)
        windowController?.add(urls: urls)
    }

    private func makeMenus() {
        let main = NSMenu()
        let applicationItem = NSMenuItem()
        main.addItem(applicationItem)
        let appMenu = NSMenu(title: "Naming Assistant")
        applicationItem.submenu = appMenu
        let show = appMenu.addItem(withTitle: "显示命名窗口", action: #selector(showWindow(_:)), keyEquivalent: "n")
        show.keyEquivalentModifierMask = [.control, .option, .command]
        show.target = self
        let settings = appMenu.addItem(withTitle: "设置…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settings.target = self
        let shortcut = appMenu.addItem(withTitle: "快捷键设置…", action: #selector(showSettings(_:)), keyEquivalent: "")
        shortcut.target = self
        appMenu.addItem(.separator())
        let servicesItem = NSMenuItem(title: "服务", action: nil, keyEquivalent: "")
        let services = NSMenu(title: "服务")
        servicesItem.submenu = services
        appMenu.addItem(servicesItem)
        NSApplication.shared.servicesMenu = services
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 Naming Assistant", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出 Naming Assistant", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileItem = NSMenuItem()
        main.addItem(fileItem)
        let fileMenu = NSMenu(title: "文件")
        fileItem.submenu = fileMenu
        let open = fileMenu.addItem(withTitle: "添加文件或文件夹…", action: #selector(addFiles(_:)), keyEquivalent: "o")
        open.target = self

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApplication.shared.mainMenu = main
    }
}

/// Services launches the application before delivering its selection. A bounded
/// memory queue covers window setup without creating a second filesystem store.
/// Only rename journals are persisted, by MacRenameCore's safe filesystem layer.
@MainActor
private final class IncomingSelectionStore {
    private var pending: [URL] = []

    func save(_ urls: [URL]) throws {
        guard urls.count <= 500 else { throw SelectionError.tooMany }
        guard urls.allSatisfy({ $0.isFileURL && ($0.host == nil || $0.host == "" || $0.host == "localhost") }) else {
            throw SelectionError.nonLocal
        }
        var known = Set(pending.map(\.absoluteString))
        let additional = urls.filter { known.insert($0.absoluteString).inserted }
        guard pending.count + additional.count <= 500 else { throw SelectionError.tooMany }
        pending.append(contentsOf: additional)
    }

    func drain() -> [URL] {
        let result = pending
        pending.removeAll(keepingCapacity: true)
        return result
    }

    private enum SelectionError: LocalizedError {
        case tooMany
        case nonLocal
        var errorDescription: String? {
            switch self {
            case .tooMany: return "一次最多处理 500 个明确选中的对象。"
            case .nonLocal: return "只接受本机文件或文件夹。"
            }
        }
    }
}
