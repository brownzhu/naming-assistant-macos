import AppKit
import MacRenameCore

/// One explicitly granted root; no launch item, recursive watch, key hooks or AI.
@MainActor
final class FolderAssistController: NSObject {
    var onRulesChange: (() -> Void)?
    var onOpenMain: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onHistoryChange: ((URL) -> Void)?
    private let coordinator: SafeRenameCoordinator
    private let monitor: FolderAssistMonitor
    private let defaults: UserDefaults
    private let enabledKey = "folderAssist.enabled.v1"
    private let bookmarkKey = "folderAssist.rootBookmark.v1"
    private var categoryPreferences = NamingPreferencesStore.categories()
    private var categoryEditor: CategoryPreferencesWindowController?
    private var glossaryEditor: GlossarySettingsWindowController?
    private var restartAfterApply = false
    private let editCategories = NSButton(title: "编辑分类词…", target: nil, action: nil)
    private let editGlossary = NSButton(title: "编辑词语转换…", target: nil, action: nil)
    private var grantedURL: URL?
    private var scoped = false
    private var generation = 0
    private var configuring = false
    private var applying = false
    private var queue: [FolderAssistObservation] = []
    private var card: FolderSuggestionPanel?
    private var active: FolderAssistObservation?
    private var statusItem: NSStatusItem?
    private var menuStatus: NSMenuItem?
    private var toggleItem: NSMenuItem?
    private var suggestionItem: NSMenuItem?
    private var lastStatus = "尚未启用。请选择一个专门存放资料的父文件夹。"
    private let rootLabel = NSTextField(wrappingLabelWithString: "尚未选择")
    private let statusLabel = NSTextField(wrappingLabelWithString: "尚未启用。请选择一个专门存放资料的父文件夹。")
    private let enabled = NSButton(checkboxWithTitle: "启用新文件夹命名建议", target: nil, action: nil)
    private let choose = NSButton(title: "选择文件夹…", target: nil, action: nil)
    private let forget = NSButton(title: "移除授权", target: nil, action: nil)
    private let categoryPopup = NSPopUpButton()

    init(coordinator: SafeRenameCoordinator, defaults: UserDefaults = .standard) {
        self.coordinator = coordinator
        self.defaults = defaults
        monitor = FolderAssistMonitor(coordinator: coordinator)
        super.init()
        monitor.onCandidate = { [weak self] observation in self?.receive(observation) }
        monitor.onStatus = { [weak self] message in
            guard let self else { return }
            setStatus(message)
            if !monitor.isRunning {
                defaults.set(false, forKey: enabledKey)
                clearSuggestions()
            }
            updateControls()
        }
    }

    var authorizedRootURL: URL? { grantedURL }

    func start() {
        makeStatusMenu()
        guard let bookmark = defaults.data(forKey: bookmarkKey) else { updateControls(); return }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)
            guard !stale else { throw AssistError.message("文件夹授权需要更新，请重新选择。") }
            retainGrant(url)
            if defaults.bool(forKey: enabledKey) { startMonitoring() }
            else { setStatus("已选择文件夹；当前未启用。") }
        } catch {
            defaults.set(false, forKey: enabledKey)
            setStatus("无法恢复文件夹授权，请重新选择。")
        }
        updateControls()
    }

    func shutdown() {
        generation += 1
        monitor.stop()
        clearSuggestions()
        releaseGrant()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    func makeSettingsView() -> NSView {
        let content = NSView()
        let title = NSTextField(labelWithString: "在 Finder 命名后，直接选建议")
        title.font = .systemFont(ofSize: 21, weight: .semibold)
        let introduction = label("选择一个父文件夹并启用。在里面新建空文件夹、输入名字并按回车，稍等片刻就会出现建议卡片。")
        let rootTitle = NSTextField(labelWithString: "只观察这个文件夹的直接子项")
        rootTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        rootLabel.font = .systemFont(ofSize: 12)
        rootLabel.textColor = .secondaryLabelColor
        rootLabel.isSelectable = true
        rootLabel.maximumNumberOfLines = 3
        choose.target = self
        choose.action = #selector(chooseRoot(_:))
        choose.bezelStyle = .rounded
        forget.target = self
        forget.action = #selector(forgetRoot(_:))
        let rootButtons = NSStackView(views: [choose, forget])
        rootButtons.spacing = 12
        enabled.target = self
        enabled.action = #selector(toggleEnabled(_:))
        let categoryTitle = label("没有明确分类线索时，默认选中")
        refreshCategoryPopup()
        categoryPopup.target = self
        categoryPopup.action = #selector(changeDefaultCategory(_:))
        let categoryRow = NSStackView(views: [categoryTitle, categoryPopup])
        categoryRow.spacing = 12
        editCategories.target = self
        editCategories.action = #selector(openCategoryEditor(_:))
        editGlossary.target = self
        editGlossary.action = #selector(openGlossaryEditor(_:))
        let ruleButtons = NSStackView(views: [editCategories, editGlossary])
        ruleButtons.spacing = 12
        let choices = label("初始显示五类。可增删分类、调整顺序、勾选显示数量，也可修改原词到英文的转换。输入有明确关键词时会推荐，最终由你选择。")
        let example = label("例如 test → 2026_10_research_test\n日期使用新文件夹的创建月份（Europe/Berlin）。")
        example.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        let scope = label("只对启用后新建的空文件夹建议；已有文件夹、子层级、工程及固定名称会跳过。复制或解压也可能产生创建事件，因此每次都需要你确认。")
        scope.textColor = .secondaryLabelColor
        let lifecycle = label("关闭主窗口后仍可使用；退出 App 后停止。不会自动登录启动。监听中断会暂停，重新启用不会补扫旧文件夹。")
        lifecycle.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 4
        let stack = NSStackView(views: [title, introduction, rootTitle, rootLabel, rootButtons, enabled, categoryRow, ruleButtons, choices, example, scope, lifecycle, statusLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
        ])
        for field in [introduction, rootLabel, choices, example, scope, lifecycle, statusLabel] {
            field.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        updateControls()
        return content
    }

    private func refreshCategoryPopup() {
        categoryPopup.removeAllItems()
        categoryPopup.addItems(withTitles: categoryPreferences.visibleOptions.map { $0.label + " · " + $0.token })
        categoryPopup.selectItem(at: categoryPreferences.visibleOptions.firstIndex(where: { $0.id == categoryPreferences.defaultID }) ?? 0)
    }

    @objc private func openCategoryEditor(_ sender: Any?) {
        guard !applying, !configuring else { return }
        let editor = CategoryPreferencesWindowController(preferences: categoryPreferences) { [weak self] value in
            guard let self else { return }
            guard !configuring else { throw AssistError.message("请等待目录启动或授权完成，再保存分类设置。") }
            try NamingPreferencesStore.save(value)
            categoryPreferences = value
            onRulesChange?()
            refreshCategoryPopup()
            if applying { restartAfterApply = true }
            else {
                clearSuggestions()
                if monitor.isRunning { startMonitoring() }
            }
            setStatus("分类规则已保存；之后的新建议使用这些分类和显示顺序。")

        }
        categoryEditor = editor
        editor.showWindow(sender)
        editor.window?.makeKeyAndOrderFront(sender)
    }

    @objc private func openGlossaryEditor(_ sender: Any?) {
        guard !applying else { return }
        let editor = GlossarySettingsWindowController { [weak self] in
            guard let self else { return }
            if !applying { clearSuggestions() }
            onRulesChange?()
            setStatus("词语转换已保存；之后生成的新建议使用更新后的词典。")
        }
        glossaryEditor = editor
        editor.showWindow(sender)
        editor.window?.makeKeyAndOrderFront(sender)
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: 13)
        return field
    }

    @objc private func chooseRoot(_ sender: Any?) {
        guard !configuring, !applying else { return }
        let panel = NSOpenPanel()
        panel.title = "选择新文件夹建议的父文件夹"
        panel.message = "只观察直接子项。请选择可独立改名的资料目录；请勿选择工程或应用目录。授权保存在本机，可随时关闭。"
        panel.prompt = "选择此文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.resolvesAliases = false
        panel.treatsFilePackagesAsDirectories = false
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url, let self else { return }
            configure(url)
        }
    }

    private func configure(_ url: URL) {
        guard !configuring, !applying else { return }
        generation += 1
        let current = generation
        monitor.stop()
        clearSuggestions()
        defaults.set(false, forKey: enabledKey)
        configuring = true
        setStatus("正在核查所选父文件夹…")
        let didStart = url.startAccessingSecurityScopedResource()
        updateControls()
        Task {
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            do {
                _ = try await coordinator.folderAssistRoot(at: url)
                guard generation == current else { return }
                let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                retainGrant(url)
                defaults.set(bookmark, forKey: bookmarkKey)
                configuring = false
                setStatus("已选择文件夹。勾选“启用”后，只对之后新建的空文件夹建议。")
            } catch {
                guard generation == current else { return }
                configuring = false
                setStatus("未启用：" + error.localizedDescription)
            }
            updateControls()
        }
    }

    @objc private func forgetRoot(_ sender: Any?) {
        guard !configuring, !applying else { return }
        generation += 1
        monitor.stop()
        clearSuggestions()
        defaults.set(false, forKey: enabledKey)
        defaults.removeObject(forKey: bookmarkKey)
        releaseGrant()
        setStatus("已移除观察授权。改名历史仍保留在本机，可在主窗口核查和撤销。")
        updateControls()
    }

    @objc private func changeDefaultCategory(_ sender: Any?) {
        guard categoryPreferences.visibleOptions.indices.contains(categoryPopup.indexOfSelectedItem) else { return }
        categoryPreferences.defaultID = categoryPreferences.visibleOptions[categoryPopup.indexOfSelectedItem].id
        do { try NamingPreferencesStore.save(categoryPreferences) }
        catch { setStatus("默认分类未保存：" + error.localizedDescription) }
    }

    @objc private func toggleEnabled(_ sender: Any?) {
        guard !configuring, !applying else { updateControls(); return }
        if monitor.isRunning {
            generation += 1
            defaults.set(false, forKey: enabledKey)
            monitor.stop()
            clearSuggestions()
            setStatus("已暂停。再次启用只观察之后新建的空文件夹。")
        } else { startMonitoring() }
        updateControls()
    }

    private func startMonitoring() {
        guard !configuring, let url = grantedURL else {
            setStatus("请先选择一个父文件夹。")
            updateControls()
            return
        }
        generation += 1
        let current = generation
        configuring = true
        updateControls()
        Task {
            do {
                try await monitor.start(rootURL: url, categoryTokens: categoryPreferences.options.map(\.token))
                guard generation == current else { return }
                defaults.set(true, forKey: enabledKey)
                configuring = false
                setStatus("运行中：在所选文件夹里新建空文件夹，输入名字后稍等约 1.2 秒。")
            } catch {
                guard generation == current else { return }
                configuring = false
                defaults.set(false, forKey: enabledKey)
                setStatus("已暂停：" + error.localizedDescription)
            }
            updateControls()
        }
    }

    private func retainGrant(_ url: URL) {
        releaseGrant()
        grantedURL = url
        scoped = url.startAccessingSecurityScopedResource()
    }

    private func releaseGrant() {
        if scoped, let grantedURL { grantedURL.stopAccessingSecurityScopedResource() }
        scoped = false
        grantedURL = nil
    }

    private func receive(_ observation: FolderAssistObservation) {
        guard monitor.isRunning else { return }
        guard active?.identity != observation.identity,
              !queue.contains(where: { $0.identity == observation.identity }) else { return }
        guard queue.count < 8 else {
            monitor.dismiss(identity: observation.identity)
            setStatus("建议较多，已跳过超出队列的对象。仍可手动添加并预览。")
            return
        }
        queue.append(observation)
        showNext()
    }

    private func showNext() {
        guard card == nil, !applying, monitor.isRunning, !queue.isEmpty else { return }
        let observation = queue.removeFirst()
        active = observation
        let panel = FolderSuggestionPanel(observation: observation, preferences: categoryPreferences,
            coordinator: coordinator, onApply: { [weak self] plan in self?.apply(plan, observation: observation) },
            onIgnore: { [weak self] in self?.dismissActive() })
        card = panel
        panel.presentPassively()
        setStatus("发现新的空文件夹，建议卡片已打开。也可从菜单栏查看当前建议。")
        updateControls()
    }

    private func dismissActive() {
        guard !applying else { return }
        if let active { monitor.dismiss(identity: active.identity) }
        card?.window?.orderOut(nil)
        card = nil
        active = nil
        updateControls()
        showNext()
    }

    private func clearSuggestions() {
        queue.removeAll()
        guard !applying else { return }
        if let active { monitor.dismiss(identity: active.identity) }
        card?.window?.orderOut(nil)
        card = nil
        active = nil
    }

    private func apply(_ plan: SafeRenamePlan, observation: FolderAssistObservation) {
        guard !applying, monitor.isRunning, active?.identity == observation.identity else {
            card?.showFailure("监听已暂停，请重新添加并预览。")
            return
        }
        applying = true
        monitor.dismiss(identity: observation.identity)
        updateControls()
        Task {
            do {
                let receipt = try await coordinator.execute(plan, confirmedByUser: true)
                onHistoryChange?(observation.root.url)
                applying = false
                if !receipt.requiresRecovery, receipt.failures.isEmpty, receipt.completed.count == 1 {
                    setStatus("已采用所选名称。可通过菜单栏“查看历史与撤销…”恢复原名。")
                    dismissActive()
                } else {
                    card?.showFailure("改名结果需要核查，请打开主窗口查看历史与撤销。" + receipt.failures.joined(separator: "\n"))
                    setStatus("存在未完成操作，请在主窗口检查历史。")
                }
            } catch {
                applying = false
                card?.showFailure("未能完成：" + error.localizedDescription)
                setStatus("改名未完成，可在主窗口检查历史。")
                onHistoryChange?(observation.root.url)
            }
            if restartAfterApply {
                restartAfterApply = false
                if monitor.isRunning { startMonitoring() }
            }
            updateControls()
        }
    }

    private func setStatus(_ text: String) {
        lastStatus = text
        statusLabel.stringValue = text
        menuStatus?.title = monitor.isRunning ? "新文件夹建议：运行中" : "新文件夹建议：已暂停"
        statusItem?.button?.toolTip = "Naming Assistant · " + text
    }

    private func updateControls() {
        rootLabel.stringValue = grantedURL?.path ?? "尚未选择"
        enabled.state = monitor.isRunning ? .on : .off
        enabled.isEnabled = !configuring && !applying && grantedURL != nil
        editCategories.isEnabled = !applying && !configuring
        editGlossary.isEnabled = !applying
        choose.isEnabled = !configuring && !applying
        forget.isEnabled = !configuring && !applying && grantedURL != nil
        toggleItem?.isEnabled = !configuring && !applying && grantedURL != nil
        toggleItem?.title = monitor.isRunning ? "暂停新文件夹建议" : "启用新文件夹建议"
        suggestionItem?.isEnabled = card != nil
        menuStatus?.title = monitor.isRunning ? "新文件夹建议：运行中" : "新文件夹建议：已暂停"
    }

    private func makeStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: "Naming Assistant")
        item.button?.toolTip = "Naming Assistant · " + lastStatus
        let menu = NSMenu()
        menu.autoenablesItems = false
        menuStatus = menu.addItem(withTitle: "新文件夹建议：已暂停", action: nil, keyEquivalent: "")
        menuStatus?.isEnabled = false
        menu.addItem(.separator())
        suggestionItem = menu.addItem(withTitle: "查看当前建议…", action: #selector(openSuggestion(_:)), keyEquivalent: "")
        suggestionItem?.target = self
        let show = menu.addItem(withTitle: "查看历史与撤销…", action: #selector(openMain(_:)), keyEquivalent: "")
        show.target = self
        let settings = menu.addItem(withTitle: "新文件夹建议设置…", action: #selector(openSettings(_:)), keyEquivalent: "")
        settings.target = self
        toggleItem = menu.addItem(withTitle: "启用新文件夹建议", action: #selector(toggleEnabled(_:)), keyEquivalent: "")
        toggleItem?.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Naming Assistant", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        item.menu = menu
        statusItem = item
    }

    @objc private func openMain(_ sender: Any?) { onOpenMain?() }
    @objc func openSuggestion(_ sender: Any?) {
        card?.window?.makeKeyAndOrderFront(sender)
        if card != nil { NSApplication.shared.activate(ignoringOtherApps: true) }
    }
    @objc private func openSettings(_ sender: Any?) { onOpenSettings?() }

    private enum AssistError: LocalizedError {
        case message(String)
        var errorDescription: String? { switch self { case .message(let text): return text } }
    }
}
