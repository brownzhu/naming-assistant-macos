import AppKit
import MacRenameCore

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
    private var choices: [NSButton] = []
    private var category: NamingCategory
    private var plan: SafeRenamePlan?
    private var revision = 0
    private var applying = false
    private let profile = NamingProfile()
    private let labels = ["生活", "科研", "工程", "学习", "管理"]

    init(observation: FolderAssistObservation, defaultCategory: NamingCategory,
         coordinator: SafeRenameCoordinator, onApply: @escaping (SafeRenamePlan) -> Void,
         onIgnore: @escaping () -> Void) {
        self.observation = observation
        self.coordinator = coordinator
        self.onApply = onApply
        self.onIgnore = onIgnore
        let recommendation = FolderCategorySuggester.recommend(for: observation.sourceURL.lastPathComponent)
        category = recommendation?.category ?? defaultCategory
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 570),
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

    private func buildInterface(_ recommendation: FolderCategoryRecommendation?) {
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
            explanation = "推荐依据：" + recommendation.matchedKeywords.joined(separator: "、") + "。五种分类均可选择。"
        } else {
            explanation = "这个名字没有明确的分类线索，已选用设置中的默认分类；请自行选择。"
        }
        let reason = NSTextField(wrappingLabelWithString: explanation)
        reason.textColor = .secondaryLabelColor
        let english = NSTextField(labelWithString: "英文简介（可修改）")
        descriptionField.placeholderString = "例如 test 或 literature_review"
        descriptionField.delegate = self
        descriptionField.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        descriptionField.stringValue = LocalNameSuggester.dictionarySuggestion(basename: observation.sourceURL.lastPathComponent).suggestion?.description ?? ""
        for (index, item) in NamingCategory.allCases.enumerated() {
            let button = NSButton(radioButtonWithTitle: labels[index] + " · " + item.rawValue, target: self, action: #selector(selectCategory(_:)))
            button.tag = index
            button.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            choices.append(button)
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
        let stack = NSStackView(views: [title, original, parent, reason, english, descriptionField] + choices + [status, buttons])
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
        for view in [original, parent, reason, descriptionField, status] as [NSView] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    @objc private func selectCategory(_ sender: NSButton) {
        guard !applying, NamingCategory.allCases.indices.contains(sender.tag) else { return }
        category = NamingCategory.allCases[sender.tag]
        refreshPreview()
    }

    func controlTextDidChange(_ obj: Notification) { refreshPreview() }

    private func refreshPreview() {
        revision += 1
        let current = revision
        plan = nil
        adopt.isEnabled = false
        var names: [String] = []
        for (index, item) in NamingCategory.allCases.enumerated() {
            choices[index].state = category == item ? .on : .off
            let request = NamingRequest(date: observation.createdAt, category: item,
                                        description: descriptionField.stringValue, kind: .projectFolder)
            let name = try? profile.suggestName(for: request)
            choices[index].title = labels[index] + " · " + (name ?? "请先填写英文简介")
            choices[index].toolTip = name
            names.append(name ?? "")
        }
        guard let index = NamingCategory.allCases.firstIndex(of: category), !names[index].isEmpty else {
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
