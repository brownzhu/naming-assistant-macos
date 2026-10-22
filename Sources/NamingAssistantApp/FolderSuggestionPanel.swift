import AppKit
import MacRenameCore

@MainActor
private final class FolderCategoryChoicesDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// A passive suggestion never activates the app or intercepts Finder's Return.
/// Editing or applying happens only after the user clicks this panel.
@MainActor
final class FolderSuggestionPanel: NSWindowController, NSTextFieldDelegate, NSWindowDelegate {
    private let observation: FolderAssistObservation
    private let coordinator: SafeRenameCoordinator
    private let onApply: (SafeRenamePlan) -> Void
    private let onIgnore: () -> Void
    private let descriptionField = NSTextField(string: "")
    private let status = NSTextField(wrappingLabelWithString: "正在检查新文件夹…")
    private let adopt = NSButton(title: "采用所选名称", target: nil, action: nil)
    private let ignore = NSButton(title: "忽略", target: nil, action: nil)
    private let options: [NamingCategoryOption]
    private var choices: [NSButton] = []
    private var selectedCategoryID: String
    private var plan: SafeRenamePlan?
    private var revision = 0
    private var applying = false
    private let profile = NamingProfile()

    init(observation: FolderAssistObservation, preferences: NamingCategoryPreferences,
         coordinator: SafeRenameCoordinator, onApply: @escaping (SafeRenamePlan) -> Void,
         onIgnore: @escaping () -> Void) {
        self.observation = observation
        self.coordinator = coordinator
        self.onApply = onApply
        self.onIgnore = onIgnore
        let visibleOptions = preferences.visibleOptions
        options = visibleOptions
        let suggested = preferences.recommendation(for: observation.sourceURL.lastPathComponent)
        let recommendation = suggested.flatMap { option in
            visibleOptions.first(where: { $0.id == option.id })
        }
        selectedCategoryID = recommendation?.id
            ?? visibleOptions.first(where: { $0.id == preferences.defaultID })?.id
            ?? visibleOptions.first?.id ?? ""
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 640),
                            styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "新文件夹命名建议"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        super.init(window: panel)
        panel.delegate = self
        buildInterface(recommendation)
        if let screen = NSScreen.main {
            let area = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: area.maxX - panel.frame.width - 24, y: area.maxY - panel.frame.height - 24))
        } else { panel.center() }
        refreshPreview()
    }

    required init?(coder: NSCoder) { nil }

    func presentPassively() { window?.orderFrontRegardless() }

    private func buildInterface(_ recommendation: NamingCategoryOption?) {
        guard let content = window?.contentView else { return }
        let title = NSTextField(labelWithString: "选一个分类，再确认名称")
        title.font = .systemFont(ofSize: 19, weight: .semibold)
        let original = NSTextField(wrappingLabelWithString: "原名：" + observation.sourceURL.lastPathComponent)
        original.isSelectable = true
        let parent = NSTextField(wrappingLabelWithString: "位置：" + observation.root.url.path)
        parent.textColor = .secondaryLabelColor
        parent.font = .systemFont(ofSize: 11)
        parent.maximumNumberOfLines = 2
        let explanation: String
        if let recommendation {
            explanation = "根据名称中的分类线索，推荐“" + recommendation.label + "”；你可以选择其他显示的分类。"
        } else {
            explanation = "这个名字没有明确的分类线索，已选用设置中的默认分类；请自行选择。"
        }
        let reason = NSTextField(wrappingLabelWithString: explanation)
        reason.textColor = .secondaryLabelColor
        let english = NSTextField(labelWithString: "英文简介（可修改）")
        descriptionField.placeholderString = "例如 test 或 literature_review"
        descriptionField.delegate = self
        descriptionField.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        descriptionField.stringValue = LocalNameSuggester.dictionarySuggestion(
            basename: observation.sourceURL.lastPathComponent, glossary: NamingPreferencesStore.glossary()
        ).suggestion?.description ?? ""
        for item in options {
            let button = NSButton(radioButtonWithTitle: item.label + " · " + item.token, target: self, action: #selector(selectCategory(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(item.id)
            button.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            button.cell?.lineBreakMode = .byTruncatingMiddle
            button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            choices.append(button)
        }
        let choiceStack = NSStackView(views: choices)
        choiceStack.orientation = .vertical
        choiceStack.alignment = .leading
        choiceStack.spacing = 8
        choiceStack.translatesAutoresizingMaskIntoConstraints = false
        let choiceDocument = FolderCategoryChoicesDocumentView()
        choiceDocument.translatesAutoresizingMaskIntoConstraints = false
        choiceDocument.addSubview(choiceStack)
        let choiceScroll = NSScrollView()
        choiceScroll.hasVerticalScroller = true
        choiceScroll.hasHorizontalScroller = false
        choiceScroll.autohidesScrollers = true
        choiceScroll.borderType = .bezelBorder
        choiceScroll.drawsBackground = false
        choiceScroll.documentView = choiceDocument
        let preferredHeight = choiceScroll.heightAnchor.constraint(equalToConstant: CGFloat(max(48, min(190, options.count * 28 + 16))))
        preferredHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            choiceDocument.leadingAnchor.constraint(equalTo: choiceScroll.contentView.leadingAnchor),
            choiceDocument.topAnchor.constraint(equalTo: choiceScroll.contentView.topAnchor),
            choiceDocument.widthAnchor.constraint(equalTo: choiceScroll.contentView.widthAnchor),
            choiceStack.topAnchor.constraint(equalTo: choiceDocument.topAnchor, constant: 8),
            choiceStack.leadingAnchor.constraint(equalTo: choiceDocument.leadingAnchor, constant: 8),
            choiceStack.trailingAnchor.constraint(equalTo: choiceDocument.trailingAnchor, constant: -8),
            choiceStack.bottomAnchor.constraint(equalTo: choiceDocument.bottomAnchor, constant: -8),
            choiceScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            choiceScroll.heightAnchor.constraint(lessThanOrEqualToConstant: 190),
            preferredHeight,
        ])
        for button in choices {
            button.widthAnchor.constraint(equalTo: choiceStack.widthAnchor).isActive = true
        }
        status.font = .systemFont(ofSize: 12)
        status.maximumNumberOfLines = 3
        status.textColor = .secondaryLabelColor
        adopt.target = self
        adopt.action = #selector(apply(_:))
        adopt.bezelStyle = .rounded
        adopt.isEnabled = false
        // Deliberately no Return key equivalent: Finder keeps its rename key.
        ignore.target = self
        ignore.action = #selector(dismiss(_:))
        let buttons = NSStackView(views: [ignore, adopt])
        buttons.spacing = 12
        let stack = NSStackView(views: [title, original, parent, reason, english, descriptionField, choiceScroll, status, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -18),
        ])
        for view in [original, parent, reason, descriptionField, choiceScroll, status] as [NSView] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    @objc private func selectCategory(_ sender: NSButton) {
        guard !applying, let id = sender.identifier?.rawValue,
              options.contains(where: { $0.id == id }) else { return }
        selectedCategoryID = id
        refreshPreview()
    }

    func controlTextDidChange(_ obj: Notification) { refreshPreview() }

    private func refreshPreview() {
        revision += 1
        let current = revision
        plan = nil
        adopt.isEnabled = false
        var names: [String] = []
        for (index, item) in options.enumerated() {
            choices[index].state = selectedCategoryID == item.id ? .on : .off
            let request = NamingRequest(date: observation.createdAt, category: .research,
                                        description: descriptionField.stringValue, kind: .projectFolder)
            let name = try? profile.suggestName(for: request, categoryToken: item.token)
            choices[index].title = item.label + " · " + (name ?? "请先填写英文简介")
            choices[index].toolTip = name
            names.append(name ?? "")
        }
        guard !options.isEmpty else {
            status.stringValue = "请先在设置中至少显示一个分类。"
            return
        }
        guard let index = options.firstIndex(where: { $0.id == selectedCategoryID }), !names[index].isEmpty else {
            status.stringValue = "请输入完整的英文简介。未知中文不会被截断或自动上传翻译。"
            return
        }
        let request = observation.renameRequest(proposedName: names[index])
        status.stringValue = "正在核查原文件夹、保护规则和名称冲突…"
        Task { [weak self] in
            guard let self else { return }
            do {
                let history = try await coordinator.history(recoverInterrupted: false)
                guard current == revision, !applying else { return }
                guard !history.contains(where: \.requiresRecovery) else {
                    status.stringValue = "存在待核查历史，请先在主窗口处理历史与撤销。"
                    return
                }
                let preview = try await coordinator.preview([request])
                guard current == revision, !applying else { return }
                plan = preview.canExecute ? preview : nil
                adopt.isEnabled = preview.canExecute
                status.stringValue = preview.canExecute
                    ? "预览已通过。日期使用这个新文件夹的创建月份；点击采用才会改名。"
                    : preview.entries.flatMap(\.issues).joined(separator: "\n")
            } catch {
                guard current == revision else { return }
                status.stringValue = "无法核查历史：" + error.localizedDescription
            }
        }
    }

    @objc private func apply(_ sender: Any?) {
        guard !applying, let plan, plan.canExecute else { return }
        setApplying(true, message: "正在安全改名…")
        onApply(plan)
    }

    func setApplying(_ value: Bool, message: String) {
        applying = value
        descriptionField.isEnabled = !value
        choices.forEach { $0.isEnabled = !value }
        ignore.isEnabled = !value
        adopt.isEnabled = false
        status.stringValue = message
    }

    func showFailure(_ message: String) {
        setApplying(false, message: message + "\n请忽略本次建议；可在主窗口检查历史。")
        plan = nil
    }

    @objc private func dismiss(_ sender: Any?) {
        guard !applying else { return }
        onIgnore()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !applying else { return false }
        onIgnore()
        return false
    }
}
