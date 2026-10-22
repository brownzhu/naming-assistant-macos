import AppKit

/// Hosts folder suggestion settings and shortcut guidance. The shortcut page
/// opens only fixed macOS settings destinations; it never edits system bindings.
@MainActor
final class ShortcutSettingsWindowController: NSWindowController {
    private let status = NSTextField(wrappingLabelWithString: "推荐组合；当前系统绑定状态未读取。每台 Mac 需要设置一次。")
    private let tabs = NSTabView()

    init(folderSettingsView: NSView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 720),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "设置 · 命名助手"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildInterface(folderSettingsView: folderSettingsView)
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func selectShortcutTab(_ shortcut: Bool) {
        tabs.selectTabViewItem(at: shortcut ? 1 : 0)
    }

    private func buildInterface(folderSettingsView: NSView) {
        guard let content = window?.contentView else { return }
        tabs.tabViewType = .topTabsBezelBorder
        tabs.font = .systemFont(ofSize: 13)
        tabs.translatesAutoresizingMaskIntoConstraints = false

        let folderTab = NSTabViewItem(identifier: "folderSuggestions")
        folderTab.label = "新文件夹建议"
        folderTab.view = folderSettingsView
        tabs.addTabViewItem(folderTab)

        let shortcutTab = NSTabViewItem(identifier: "shortcuts")
        shortcutTab.label = "快捷键"
        let shortcutView = NSView()
        buildShortcutInterface(in: shortcutView)
        shortcutTab.view = shortcutView
        tabs.addTabViewItem(shortcutTab)

        content.addSubview(tabs)
        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            tabs.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            tabs.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            tabs.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
        selectShortcutTab(false)
    }

    private func buildShortcutInterface(in content: NSView) {
        let title = NSTextField(labelWithString: "快捷启动")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        let introduction = label("在 Finder 中选中文件后，使用服务快捷键打开命名预览。")
        let recommended = NSTextField(labelWithString: "推荐快捷键")
        recommended.textColor = .secondaryLabelColor
        let keys = NSTextField(labelWithString: "⌃⌥⌘N")
        keys.font = .systemFont(ofSize: 34, weight: .medium)
        keys.isSelectable = true
        let keyNames = label("Control + Option + Command + N")
        keyNames.textColor = .secondaryLabelColor
        let service = label("服务名称：建议标准名称 / Suggest Standard Names")
        service.isSelectable = true
        let jump = NSButton(title: "打开系统快捷键设置", target: self, action: #selector(openServiceSettings(_:)))
        jump.bezelStyle = .rounded
        let keyboard = NSButton(title: "打开键盘设置", target: self, action: #selector(openKeyboardSettings(_:)))
        let buttons = NSStackView(views: [jump, keyboard])
        buttons.orientation = .horizontal
        buttons.spacing = 12
        let steps = label("1. 在系统快捷键窗口选择“服务”。\n2. 展开“文件和文件夹”，找到并勾选“建议标准名称”。\n3. 双击右侧快捷键区域，按下推荐组合（也可自选）。")
        steps.maximumNumberOfLines = 0
        let note = label("不同 macOS 版本可能只打开键盘页面；请再点击“键盘快捷键…”→“服务”。最终绑定需要在系统设置中完成。")
        note.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.maximumNumberOfLines = 3
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let footer = label("Naming Assistant" + (version.map { " · " + $0 } ?? " · 开发构建"))
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .tertiaryLabelColor
        let stack = NSStackView(views: [title, introduction, recommended, keys, keyNames, service, buttons, steps, note, status, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
        ])
        for field in [introduction, keyNames, service, steps, note, status, footer] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: 13)
        return field
    }

    @objc private func openServiceSettings(_ sender: Any?) {
        openSettings([
            "x-apple.systempreferences:com.apple.preference.keyboard?Services",
            "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts",
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
        ])
    }

    @objc private func openKeyboardSettings(_ sender: Any?) {
        openSettings([
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.keyboard",
        ])
    }

    private func openSettings(_ destinations: [String]) {
        for destination in destinations {
            if let url = URL(string: destination), NSWorkspace.shared.open(url) {
                // A successful URL dispatch does not prove that macOS honored
                // the requested anchor, nor that the shortcut has been set.
                status.stringValue = "已请求打开系统键盘设置。若未进入“服务”，请选择“键盘快捷键…”→“服务”。"
                return
            }
        }
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences"),
           NSWorkspace.shared.open(appURL) {
            status.stringValue = "已请求打开系统设置。请进入“键盘”→“键盘快捷键…”→“服务”。"
        } else {
            status.stringValue = "未能打开系统设置。请手动进入“系统设置”→“键盘”→“键盘快捷键…”→“服务”。"
        }
    }
}
