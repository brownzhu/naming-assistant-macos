import AppKit
import MacRenameCore

@MainActor
private final class NamingRow {
    let url: URL
    let isDirectory: Bool
    let suffix: String
    let originalStem: String
    let isStandardName: Bool
    var included = true
    var category: NamingCategory = .research
    var description: String
    var date = Date()
    var dateConfirmed = false
    var version = ""
    var proposedName = "尚未生成"
    var status = "等待预览"
    var inputError: String?
    var suggestionInfo: String

    init(url: URL, isDirectory: Bool) {
        self.url = url
        self.isDirectory = isDirectory
        self.version = isDirectory ? "" : "1"
        self.suffix = isDirectory ? "" : SafeFilenameExtension.suffix(for: url.lastPathComponent)
        let stem = isDirectory ? url.lastPathComponent : SafeFilenameExtension.stem(for: url.lastPathComponent)
        self.originalStem = stem
        self.isStandardName = NamingProfile.matchesStandardStem(stem, kind: isDirectory ? .projectFolder : .file)
        let fallback = LocalNameSuggester.dictionarySuggestion(basename: stem)
        if let suggestion = fallback.suggestion, suggestion.source == .localDictionary {
            self.description = suggestion.description
            self.suggestionInfo = "来源：本地词典；请核对英文含义。" + localModelAvailabilityText(fallback.modelAvailability)
        } else {
            self.description = (try? NamingProfile.snakeCase(stem)) ?? ""
            self.suggestionInfo = (self.description.isEmpty ? "未知词语请手动填写英文简介。" : "") + localModelAvailabilityText(fallback.modelAvailability)
        }
        if isStandardName {
            included = false
            proposedName = url.lastPathComponent
            status = "已符合命名格式，默认保留"
        }
    }
}

@MainActor
final class NamingWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private var rows: [NamingRow] = []
    private var editorIndex: Int?
    private var revision = 0
    private var currentPlan: SafeRenamePlan?
    private var latestReceipt: SafeRenameReceipt?
    private var operationGeneration = 0
    private var requiresManualRecovery = false
    private var busy = false
    private var authorizingSelection = false
    private var queuedSelections: [URL] = []
    private var parentAccess: [String: ParentAccessLease] = [:]
    private let profile = NamingProfile()
    private let coordinator: SafeRenameCoordinator

    private let table = NSTableView()
    private let summary = NSTextField(wrappingLabelWithString: "添加文件后，选择一行填写英文简介。日期默认 undated；核实后再勾选日期。")
    private let originalPath = NSTextField(wrappingLabelWithString: "尚未选择文件")
    private let descriptionField = NSTextField(string: "")
    private let suggestButton = NSButton(title: "本机生成英文建议", target: nil, action: nil)
    private let suggestionStatus = NSTextField(wrappingLabelWithString: "仅使用原文件名，不读取文件内容。")
    private let categoryPopup = NSPopUpButton()
    private let versionField = NSTextField(string: "")
    private let dateCheckbox = NSButton(checkboxWithTitle: "使用右侧日期（我已核实）", target: nil, action: nil)
    private let datePicker = NSDatePicker()
    private let kindLabel = NSTextField(labelWithString: "文件日期：YYYY_MM_DD；文件夹：YYYY_MM")
    private let previewButton = NSButton(title: "生成预览", target: nil, action: nil)
    private let applyButton = NSButton(title: "确认改名…", target: nil, action: nil)
    private let undoButton = NSButton(title: "撤销上次操作…", target: nil, action: nil)
    private let removeButton = NSButton(title: "移除选中项", target: nil, action: nil)
    private let addButton = NSButton(title: "添加文件或文件夹…", target: nil, action: nil)

    private let categoryLabels: [(NamingCategory, String)] = [
        (.life, "生活 · life"), (.research, "科研 · research"),
        (.engineering, "工程 · engineering"), (.learning, "学习 · learning"), (.admin, "管理 · admin"),
    ]

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        coordinator = SafeRenameCoordinator(journalDirectory: base.appendingPathComponent("NamingAssistant/History", isDirectory: true))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1160, height: 780), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Naming Assistant · 文件命名助手"
        window.minSize = NSSize(width: 940, height: 700)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildInterface()
        window.center()
        Task { await restoreUndoHistory() }
    }

    required init?(coder: NSCoder) { nil }

    @objc func chooseFiles(_ sender: Any?) {
        guard !busy, let window else { return }
        let panel = NSOpenPanel()
        panel.title = "选择要预览命名的文件或文件夹"
        panel.prompt = "添加"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = false
        panel.treatsFilePackagesAsDirectories = false
        panel.beginSheetModal(for: window) { [weak self] result in
            guard result == .OK else { return }
            self?.add(urls: panel.urls)
        }
    }

    func add(urls: [URL]) {
        guard !busy else {
            if authorizingSelection {
                queuedSelections.append(contentsOf: urls.prefix(max(0, 500 - queuedSelections.count)))
            } else {
                showMessage("正在处理当前操作", "完成后请再次添加文件。")
            }
            return
        }
        saveEditor()
        var known = Set(rows.map { $0.url.standardizedFileURL.path })
        var skipped = max(0, urls.count - 500)
        var candidates: [URL] = []
        for url in urls.prefix(500) {
            guard rows.count + candidates.count < 500 else { skipped += 1; continue }
            guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost" else { skipped += 1; continue }
            guard !url.pathComponents.contains("."), !url.pathComponents.contains("..") else { skipped += 1; continue }
            let local = url.standardizedFileURL
            guard known.insert(local.path).inserted else { continue }
            candidates.append(local)
        }
        guard !candidates.isEmpty else { return }
        authorizingSelection = true
        setBusy(true, message: "请仅授权所选对象的直接父文件夹。取消授权会跳过该文件夹中的对象。")
        Task {
            var authorized: [URL] = []
            var parents: [URL] = []
            var seenParents = Set<String>()
            for candidate in candidates {
                let parent = candidate.deletingLastPathComponent().standardizedFileURL
                if seenParents.insert(parent.path).inserted { parents.append(parent) }
            }
            for parent in parents {
                let hasAccess: Bool
                if parentAccess[parent.path] != nil { hasAccess = true }
                else { hasAccess = await requestParentAccess(parent) }
                if hasAccess {
                    authorized.append(contentsOf: candidates.filter { $0.deletingLastPathComponent().standardizedFileURL.path == parent.path })
                }
            }
            skipped += candidates.count - authorized.count
            for url in authorized {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { skipped += 1; continue }
                rows.append(NamingRow(url: url, isDirectory: isDirectory.boolValue))
            }
            authorizingSelection = false
            setBusy(false)
            finishAdding(skipped: skipped)
            if !queuedSelections.isEmpty {
                let queued = queuedSelections
                queuedSelections.removeAll(keepingCapacity: true)
                add(urls: queued)
            }
        }
    }

    private func requestParentAccess(_ parent: URL) async -> Bool {
        guard let window else { return false }
        let panel = NSOpenPanel()
        panel.title = "仅允许在此文件夹内改名"
        panel.message = "请选择以下精确文件夹：\n\(parent.path)\n\n请确认这里是可独立改名的资料或导出目录，没有工程或其他文档依赖这些文件名。只处理你明确添加的对象，不展开文件夹。取消会跳过这些对象。"
        panel.prompt = "允许此文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = parent
        let validator = ExactParentPanelDelegate(expected: parent)
        panel.delegate = validator
        return await withCheckedContinuation { continuation in
            panel.beginSheetModal(for: window) { [weak self] response in
                // NSOpenPanel's delegate is weak; retain it through completion.
                _ = validator
                guard response == .OK, let selected = panel.url,
                      validator.accepts(selected), let self else {
                    continuation.resume(returning: false)
                    return
                }
                self.parentAccess[parent.path] = ParentAccessLease(url: selected)
                continuation.resume(returning: true)
            }
        }
    }

    private func finishAdding(skipped: Int) {
        invalidatePreview()
        table.reloadData()
        if table.selectedRow < 0, !rows.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        loadEditor()
        if requiresManualRecovery, let receipt = latestReceipt {
            summary.stringValue = recoveryMessage(receipt)
        } else {
            summary.stringValue = "已添加 \(rows.count) 个对象。仅处理明确选中的对象；不会展开文件夹。" + (skipped > 0 ? " 已跳过 \(skipped) 个无效或超出上限的对象。" : "")
        }
    }

    private func buildInterface() {
        guard let content = window?.contentView else { return }
        let title = NSTextField(labelWithString: "先预览，再确认；文件内容与完整扩展名保持原样。")
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        let subtitle = NSTextField(wrappingLabelWithString: "本机处理 · 无云端 AI · 工程目录、固定名称和应用包由保护规则跳过。快捷键：⌃⌥⌘N（Finder 中首次需设置服务快捷键）。")
        subtitle.textColor = .secondaryLabelColor
        subtitle.font = .systemFont(ofSize: 12)

        addButton.target = self
        addButton.action = #selector(chooseFiles(_:))
        removeButton.target = self
        removeButton.action = #selector(removeSelected(_:))
        let topButtons = NSStackView(views: [addButton, removeButton])
        topButtons.orientation = .horizontal
        topButtons.spacing = 10

        table.delegate = self
        table.dataSource = self
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 38
        table.allowsMultipleSelection = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.registerForDraggedTypes([.fileURL])
        let definitions: [(String, String, CGFloat)] = [
            ("include", "处理", 48), ("original", "原名称", 260), ("proposed", "建议名称", 380), ("status", "检查结果", 360),
        ]
        for (identifier, title, width) in definitions {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            column.minWidth = identifier == "include" ? 48 : 100
            table.addTableColumn(column)
        }
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 190).isActive = true

        originalPath.textColor = .secondaryLabelColor
        originalPath.font = .systemFont(ofSize: 11)
        originalPath.maximumNumberOfLines = 2
        originalPath.isSelectable = true
        descriptionField.placeholderString = "例如 cem_eit_uniqueness_proof；中文资料请填写英文简介"
        descriptionField.delegate = self
        descriptionField.target = self
        descriptionField.action = #selector(editorChanged(_:))
        descriptionField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        suggestButton.target = self
        suggestButton.action = #selector(suggestEnglishDescription(_:))
        suggestButton.toolTip = "只向 Apple 本机模型提交原文件名；模型不可用时尝试本地词典。不会读取内容或执行改名。"
        suggestionStatus.font = .systemFont(ofSize: 11)
        suggestionStatus.textColor = .secondaryLabelColor
        suggestionStatus.maximumNumberOfLines = 3
        suggestionStatus.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let suggestionControls = NSStackView(views: [suggestButton, suggestionStatus])
        suggestionControls.orientation = .horizontal
        suggestionControls.spacing = 12
        suggestionControls.alignment = .centerY
        categoryPopup.addItems(withTitles: categoryLabels.map(\.1))
        categoryPopup.selectItem(at: 1)
        categoryPopup.target = self
        categoryPopup.action = #selector(editorChanged(_:))
        versionField.placeholderString = "可留空，例如 1"
        versionField.delegate = self
        versionField.target = self
        versionField.action = #selector(editorChanged(_:))
        versionField.widthAnchor.constraint(equalToConstant: 155).isActive = true
        dateCheckbox.target = self
        dateCheckbox.action = #selector(editorChanged(_:))
        datePicker.datePickerStyle = .textFieldAndStepper
        datePicker.datePickerElements = [.yearMonthDay]
        datePicker.locale = Locale(identifier: "en_GB")
        datePicker.timeZone = TimeZone(identifier: "Europe/Berlin")
        datePicker.target = self
        datePicker.action = #selector(editorChanged(_:))
        datePicker.widthAnchor.constraint(equalToConstant: 145).isActive = true
        let dates = NSStackView(views: [dateCheckbox, datePicker, kindLabel])
        dates.orientation = .horizontal
        dates.spacing = 12
        let categories = NSStackView(views: [categoryPopup, NSTextField(labelWithString: "版本："), versionField])
        categories.orientation = .horizontal
        categories.spacing = 10
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "当前对象："), originalPath],
            [NSTextField(labelWithString: "分类 / 版本："), categories],
            [NSTextField(labelWithString: "英文简介："), descriptionField],
            [NSTextField(labelWithString: "本机建议："), suggestionControls],
            [NSTextField(labelWithString: "资料日期："), dates],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).width = 90
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill

        let note = NSTextField(wrappingLabelWithString: "日期只采用你核实的资料日期，不使用下载时间或文件修改时间。未勾选时以 undated 命名。非空文件夹暂时保留，科研工程建议只命名导出文件。")
        note.font = .systemFont(ofSize: 12)
        note.textColor = .secondaryLabelColor
        previewButton.target = self
        previewButton.action = #selector(generatePreview(_:))
        previewButton.keyEquivalent = "r"
        previewButton.keyEquivalentModifierMask = [.command]
        applyButton.target = self
        applyButton.action = #selector(applyRename(_:))
        applyButton.bezelStyle = .rounded
        undoButton.target = self
        undoButton.action = #selector(undoRename(_:))
        summary.font = .systemFont(ofSize: 12)
        summary.maximumNumberOfLines = 3
        let bottomButtons = NSStackView(views: [previewButton, applyButton, undoButton])
        bottomButtons.orientation = .horizontal
        bottomButtons.spacing = 10
        let stack = NSStackView(views: [title, subtitle, topButtons, scroll, grid, note, bottomButtons, summary])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            subtitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
            grid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            note.widthAnchor.constraint(equalTo: stack.widthAnchor),
            summary.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        updateControls()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row), let identifier = tableColumn?.identifier.rawValue else { return nil }
        let item = rows[row]
        if identifier == "include" {
            let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleIncluded(_:)))
            checkbox.state = item.included ? .on : .off
            checkbox.tag = row
            checkbox.isEnabled = !busy
            return checkbox
        }
        let text: String
        switch identifier {
        case "original": text = (item.isDirectory ? "▸ " : "") + item.url.lastPathComponent
        case "proposed": text = item.proposedName
        default:
            text = item.status == "状态待核查" ? item.status : (item.included ? item.status : (item.isStandardName ? (item.status == "已改名" ? "已改名" : "已符合命名格式，默认保留") : "已排除"))
        }
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingMiddle
        label.toolTip = text
        if identifier == "status", item.status != "可以改名" { label.textColor = .secondaryLabelColor }
        return label
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        saveEditor()
        loadEditor()
    }

    func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard !busy else { return [] }
        tableView.setDropRow(-1, dropOperation: .on)
        return .copy
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return false }
        add(urls: urls)
        return true
    }

    func controlTextDidChange(_ obj: Notification) {
        if let field = obj.object as? NSTextField, field === descriptionField,
           let index = editorIndex, rows.indices.contains(index) {
            let info = "来源：手动填写。" + localModelAvailabilityText(LocalNameSuggester.modelAvailability())
            rows[index].suggestionInfo = info
            suggestionStatus.stringValue = info
            suggestionStatus.toolTip = info
        }
        invalidatePreview()
    }

    @objc private func editorChanged(_ sender: Any?) {
        saveEditor()
        invalidatePreview()
        datePicker.isEnabled = editorIndex != nil && dateCheckbox.state == .on && !busy
    }

    @objc private func toggleIncluded(_ sender: NSButton) {
        guard rows.indices.contains(sender.tag), !busy else { return }
        rows[sender.tag].included = sender.state == .on
        invalidatePreview()
        table.reloadData()
    }

    @objc private func removeSelected(_ sender: Any?) {
        guard !busy, rows.indices.contains(table.selectedRow) else { return }
        rows.remove(at: table.selectedRow)
        editorIndex = nil
        invalidatePreview()
        table.reloadData()
        loadEditor()
    }

    private func saveEditor() {
        guard let index = editorIndex, rows.indices.contains(index) else { return }
        rows[index].description = descriptionField.stringValue
        rows[index].category = categoryLabels[max(0, categoryPopup.indexOfSelectedItem)].0
        rows[index].version = versionField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        rows[index].date = datePicker.dateValue
        rows[index].dateConfirmed = dateCheckbox.state == .on
    }

    private func loadEditor() {
        editorIndex = rows.indices.contains(table.selectedRow) ? table.selectedRow : nil
        guard let index = editorIndex else {
            originalPath.stringValue = "尚未选择文件"
            descriptionField.stringValue = ""
            suggestionStatus.stringValue = localModelAvailabilityText(LocalNameSuggester.modelAvailability())
            versionField.stringValue = ""
            dateCheckbox.state = .off
            updateControls()
            return
        }
        let row = rows[index]
        originalPath.stringValue = row.url.path
        descriptionField.stringValue = row.description
        suggestionStatus.stringValue = row.suggestionInfo
        suggestionStatus.toolTip = row.suggestionInfo
        categoryPopup.selectItem(at: categoryLabels.firstIndex { $0.0 == row.category } ?? 1)
        versionField.stringValue = row.version
        datePicker.dateValue = row.date
        dateCheckbox.state = row.dateConfirmed ? .on : .off
        kindLabel.stringValue = row.isDirectory ? "文件夹：YYYY_MM" : "文件：YYYY_MM_DD"
        updateControls()
    }

    @objc private func suggestEnglishDescription(_ sender: Any?) {
        guard !busy, !requiresManualRecovery, let index = editorIndex, rows.indices.contains(index) else { return }
        saveEditor()
        let row = rows[index]
        let basename = row.originalStem
        invalidatePreview()
        setBusy(true, message: "正在根据原文件名生成本机英文建议；不会读取文件内容或执行改名…")
        Task {
            let result = await LocalNameSuggester().suggest(basename: basename, useOnDeviceModel: true)
            // The table is disabled during generation. Identity is checked as
            // well so a late result can never be applied to a different item.
            guard rows.contains(where: { $0 === row }) else {
                setBusy(false, message: "原对象已移除，未应用英文建议。")
                return
            }
            if let suggestion = result.suggestion { row.description = suggestion.description }
            row.suggestionInfo = suggestionResultText(result)
            if let selected = editorIndex, rows.indices.contains(selected), rows[selected] === row {
                descriptionField.stringValue = row.description
                suggestionStatus.stringValue = row.suggestionInfo
                suggestionStatus.toolTip = row.suggestionInfo
            }
            invalidatePreview()
            setBusy(false, message: row.suggestionInfo + " 请核对英文简介，再生成预览。")
        }
    }

    private func suggestionResultText(_ result: LocalNameSuggestionResult) -> String {
        let availability = localModelAvailabilityText(result.modelAvailability)
        let failure = result.modelAttemptFailed ? "本机模型未返回可用建议，已尝试本地回退。" : ""
        switch result.status {
        case .suggested:
            let source: String
            switch result.suggestion?.source {
            case .appleOnDevice: source = "Apple 本机模型"
            case .localDictionary: source = "本地词典"
            case .existingEnglish: source = "原英文名称规范化"
            case nil: source = "无可用来源"
            }
            return "来源：\(source)。" + failure + availability
        case .needsManualEnglish:
            return failure + "无法可靠生成，请手动填写英文简介。" + availability
        case .invalidInput:
            return "原文件名不满足本机建议的输入限制，请手动填写英文简介。" + availability
        case .cancelled:
            return "本机建议已取消，现有英文简介保持原样。" + availability
        }
    }

    private func invalidatePreview() {
        revision += 1
        currentPlan = nil
        for row in rows {
            if row.status == "状态待核查" { continue }
            if row.isStandardName && !row.included {
                row.proposedName = row.url.lastPathComponent
                row.status = "已符合命名格式，默认保留"
            } else {
                row.proposedName = "尚未生成"
                row.status = "设置已变更，请重新预览"
            }
        }
        table.reloadData()
        updateControls()
    }

    @objc private func generatePreview(_ sender: Any?) {
        guard !busy, !requiresManualRecovery else { return }
        saveEditor()
        revision += 1
        let capturedRevision = revision
        currentPlan = nil
        var requests: [SafeRenameRequest] = []
        for row in rows where row.included {
            row.inputError = nil
            do {
                let version: Int?
                if row.version.isEmpty { version = nil }
                else if row.version.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(row.version), number > 0 { version = number }
                else { throw InputError.invalidVersion }
                let request = NamingRequest(date: row.dateConfirmed ? row.date : nil, category: row.category, description: row.description, kind: row.isDirectory ? .projectFolder : .file, version: version, fileExtension: row.suffix)
                row.proposedName = try profile.suggestName(for: request)
            } catch {
                row.proposedName = row.url.lastPathComponent
                row.inputError = localizedInputError(error)
            }
            requests.append(SafeRenameRequest(sourceURL: row.url, proposedName: row.proposedName))
        }
        guard !requests.isEmpty else {
            summary.stringValue = "请先添加并勾选需要处理的文件。"
            return
        }
        setBusy(true, message: "正在检查保护规则、名称冲突和文件状态…")
        Task {
            do {
                let fullPlan = try await coordinator.preview(requests)
                guard capturedRevision == revision else { setBusy(false); return }
                var readyRequests: [SafeRenameRequest] = []
                for entry in fullPlan.entries {
                    guard let row = rows.first(where: { $0.url == entry.sourceURL }) else { continue }
                    var reasons = entry.issues
                    if let inputError = row.inputError { reasons.insert(inputError, at: 0) }
                    row.status = reasons.isEmpty && entry.isReady ? "可以改名" : (reasons.isEmpty ? "无需改名" : reasons.joined(separator: "；"))
                    if entry.isReady && row.inputError == nil {
                        readyRequests.append(SafeRenameRequest(sourceURL: entry.sourceURL, proposedName: entry.proposedName))
                    }
                }
                currentPlan = readyRequests.isEmpty ? nil : try await coordinator.preview(readyRequests)
                table.reloadData()
                setBusy(false, message: "预览完成：\(readyRequests.count) 项可改名，\(requests.count - readyRequests.count) 项需检查或已保护。核对建议后点击“确认改名”。")
            } catch {
                currentPlan = nil
                setBusy(false, message: "预览失败：\(error.localizedDescription)")
            }
        }
    }

    @objc private func applyRename(_ sender: Any?) {
        guard !busy, !requiresManualRecovery, let plan = currentPlan, plan.canExecute else { return }
        let alert = NSAlert()
        alert.messageText = "确认修改 \(plan.entries.count) 个对象的名称？"
        alert.informativeText = "请确认这些文件可以独立改名，没有工程或其他文档依赖原名。保护规则无法识别所有自定义工程布局。\n\n仅处理预览中“可以改名”的对象。执行时会再次核对文件身份和目标冲突，并保存本地撤销记录。文件内容不变。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确认改名")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        operationGeneration += 1
        setBusy(true, message: "正在改名并记录操作…")
        Task {
            do {
                let initialReceipt = try await coordinator.execute(plan, confirmedByUser: true)
                let (receipt, recoveryNote) = await resolveInterruptedReceipt(initialReceipt)
                if receipt.requiresRecovery || (!requiresManualRecovery && !receipt.completed.isEmpty) { latestReceipt = receipt }
                let completed = Dictionary(uniqueKeysWithValues: receipt.completed.map { ($0.sourceURL, $0.destinationURL) })
                for (source, destination) in completed {
                    if let index = rows.firstIndex(where: { $0.url == source }) {
                        let prior = rows[index]
                        let replacement = NamingRow(url: destination, isDirectory: prior.isDirectory)
                        replacement.category = prior.category
                        replacement.description = prior.description
                        replacement.date = prior.date
                        replacement.dateConfirmed = prior.dateConfirmed
                        replacement.version = prior.version
                        replacement.proposedName = destination.lastPathComponent
                        replacement.status = "已改名"
                        replacement.included = false
                        rows[index] = replacement
                    }
                }
                if receipt.requiresRecovery {
                    let confirmedSources = Set(receipt.completed.map(\.sourceURL))
                    for row in rows where plan.entries.contains(where: { $0.sourceURL == row.url }) && !confirmedSources.contains(row.url) {
                        row.status = "状态待核查"
                    }
                }
                currentPlan = nil
                editorIndex = nil
                table.reloadData()
                loadEditor()
                let text = requiresManualRecovery
                    ? recoveryMessage(latestReceipt ?? receipt, note: recoveryNote)
                    : "已完成 \(receipt.completed.count) 项。" + (receipt.failures.isEmpty ? "撤销记录已保存在本机。" : "\n" + receipt.failures.joined(separator: "\n"))
                setBusy(false, message: text)
                if requiresManualRecovery || !receipt.failures.isEmpty { showMessage(requiresManualRecovery ? "状态待核查" : "部分操作未完成", text) }
            } catch {
                currentPlan = nil
                setBusy(false, message: "改名未完成：\(error.localizedDescription)。请重新预览。")
                showMessage("改名未完成", error.localizedDescription)
            }
        }
    }

    @objc private func undoRename(_ sender: Any?) {
        guard !busy, let priorReceipt = latestReceipt else { return }
        setBusy(true, message: "正在核对操作历史…")
        Task {
            var seenParents = Set<String>()
            for location in priorReceipt.recoveryParentURLs {
                let parent = location.standardizedFileURL
                guard seenParents.insert(parent.path).inserted, parentAccess[parent.path] == nil else { continue }
                guard await requestParentAccess(parent) else {
                    setBusy(false, message: "已取消文件夹授权，未执行撤销。")
                    return
                }
            }
            let (receipt, recoveryNote) = await resolveInterruptedReceipt(priorReceipt)
            guard !receipt.requiresRecovery, !requiresManualRecovery else {
                currentPlan = nil
                let message = recoveryMessage(latestReceipt ?? receipt, note: recoveryNote)
                setBusy(false, message: message)
                showMessage("状态待核查", message)
                return
            }
            guard !receipt.completed.isEmpty else {
                currentPlan = nil
                setBusy(false, message: "历史核查完成，目前没有待撤销的已确认改名。请重新添加相关文件并预览，以核对当前位置。")
                return
            }
            let alert = NSAlert()
            alert.messageText = "撤销最近一次改名？"
            alert.informativeText = "将核对已改名文件的身份和原位置。文件已被替换、修改或原名被占用时，工具会拒绝相关操作，不覆盖任何已有文件。"
            alert.addButton(withTitle: "确认撤销")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { setBusy(false); return }
            operationGeneration += 1
            setBusy(true, message: "正在核对并撤销…")
            do {
                let initialResult = try await coordinator.undo(receipt, confirmedByUser: true)
                let (result, recoveryNote) = await resolveInterruptedReceipt(initialResult)
                let historyNote: String?
                do {
                    selectHistory(try await coordinator.history(recoverInterrupted: false))
                    historyNote = nil
                } catch {
                    requiresManualRecovery = true
                    latestReceipt = result
                    historyNote = "读取历史记录失败：\(error.localizedDescription)"
                }
                currentPlan = nil
                // Receipt.completed means renames still in effect. Only the
                // records absent from the returned receipt have been restored.
                let restored = result.requiresRecovery ? [] : receipt.completed.filter { original in
                    !result.completed.contains { remaining in
                        remaining.sourceURL == original.sourceURL && remaining.destinationURL == original.destinationURL
                    }
                }
                for record in restored {
                    if let index = rows.firstIndex(where: { $0.url == record.destinationURL || $0.url == record.sourceURL }) {
                        rows[index] = NamingRow(url: record.sourceURL, isDirectory: rows[index].isDirectory)
                        rows[index].status = "已恢复原名，请重新预览"
                    }
                }
                if result.requiresRecovery {
                    for row in rows where receipt.completed.contains(where: { $0.sourceURL == row.url || $0.destinationURL == row.url }) {
                        row.status = "状态待核查"
                    }
                }
                editorIndex = nil
                table.reloadData()
                loadEditor()
                let message = requiresManualRecovery
                    ? recoveryMessage(latestReceipt ?? result, note: recoveryNote ?? historyNote)
                    : "已撤销 \(restored.count) 项，仍有 \(result.completed.count) 项保留改名。" + (result.failures.isEmpty ? "" : "\n" + result.failures.joined(separator: "\n"))
                setBusy(false, message: message)
                if requiresManualRecovery || !result.failures.isEmpty { showMessage(requiresManualRecovery ? "状态待核查" : "部分撤销未完成", message) }
            } catch {
                setBusy(false, message: "撤销未完成：\(error.localizedDescription)")
                showMessage("撤销未完成", error.localizedDescription)
            }
        }
    }

    private func restoreUndoHistory() async {
        let generation = operationGeneration
        do {
            let history = try await coordinator.history(recoverInterrupted: false)
            guard generation == operationGeneration, latestReceipt == nil else { return }
            selectHistory(history)
            if let receipt = latestReceipt, requiresManualRecovery {
                summary.stringValue = recoveryMessage(receipt)
            }
            updateControls()
        } catch {
            guard generation == operationGeneration else { return }
            summary.stringValue = "无法读取历史记录：\(error.localizedDescription)。仍可添加文件进行预览。"
        }
    }

    private func resolveInterruptedReceipt(_ receipt: SafeRenameReceipt) async -> (SafeRenameReceipt, String?) {
        guard receipt.requiresRecovery || requiresManualRecovery else { return (receipt, nil) }
        for parent in receipt.recoveryParentURLs where parentAccess[parent.standardizedFileURL.path] == nil {
            guard await requestParentAccess(parent.standardizedFileURL) else {
                requiresManualRecovery = true
                return (receipt, "已取消文件夹授权，操作状态保持待核查。")
            }
        }
        do {
            // Recover only this authorized journal. Reading the remaining
            // history never probes documents in other, unapproved folders.
            let refreshed = receipt.requiresRecovery ? try await coordinator.recover(receipt) : receipt
            let history = try await coordinator.history(recoverInterrupted: false)
            selectHistory(history)
            requiresManualRecovery = refreshed.requiresRecovery || requiresManualRecovery
            return (refreshed, nil)
        } catch {
            requiresManualRecovery = true
            return (receipt, "历史核查失败：\(error.localizedDescription)")
        }
    }

    private func selectHistory(_ history: [SafeRenameReceipt]) {
        requiresManualRecovery = history.contains(where: \.requiresRecovery)
        latestReceipt = history.last(where: \.requiresRecovery) ?? history.last(where: { !$0.completed.isEmpty })
    }

    private func recoveryMessage(_ receipt: SafeRenameReceipt, note: String? = nil) -> String {
        var parts = ["存在状态待核查的操作，已停止新的改名。不会把未确认项目显示为成功。请先重试历史核查；若仍无法确认，请人工检查本地历史记录和文件位置。", "历史目录：\(receipt.journalURL.deletingLastPathComponent().path)"]
        if let note { parts.append(note) }
        parts.append(contentsOf: receipt.failures)
        return parts.joined(separator: "\n")
    }

    private func setBusy(_ value: Bool, message: String? = nil) {
        busy = value
        if let message { summary.stringValue = message }
        updateControls()
        table.reloadData()
    }

    private func updateControls() {
        let hasSelection = editorIndex != nil && !busy
        descriptionField.isEnabled = hasSelection
        suggestButton.isEnabled = hasSelection && !requiresManualRecovery
        categoryPopup.isEnabled = hasSelection
        versionField.isEnabled = hasSelection
        dateCheckbox.isEnabled = hasSelection
        datePicker.isEnabled = hasSelection && dateCheckbox.state == .on
        addButton.isEnabled = !busy
        removeButton.isEnabled = hasSelection
        previewButton.isEnabled = !busy && !requiresManualRecovery && !rows.isEmpty
        applyButton.isEnabled = !busy && !requiresManualRecovery && (currentPlan?.canExecute ?? false)
        undoButton.isEnabled = !busy && latestReceipt != nil
        undoButton.title = requiresManualRecovery ? "核查历史并撤销…" : "撤销上次操作…"
        table.isEnabled = !busy
    }

    private func showMessage(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    private func localizedInputError(_ error: Error) -> String {
        guard let naming = error as? NamingProfileError else { return error.localizedDescription }
        switch naming {
        case .emptyDescription: return "请填写英文简介"
        case .descriptionRequiresEnglish: return "请填写英文简介；此版本不会自动翻译中文"
        case .invalidVersion: return "版本必须为正整数"
        default: return naming.localizedDescription
        }
    }

    private enum InputError: LocalizedError {
        case invalidVersion
        var errorDescription: String? { "版本必须为正整数，或留空。" }
    }
}

/// The grant is kept only in memory for this application session. Some
/// non-sandboxed apps return false here; NSOpenPanel still supplies the explicit
/// macOS file-access consent, so no wider directory grant is requested.
private final class ParentAccessLease {
    let url: URL
    private let didStart: Bool

    init(url: URL) {
        self.url = url
        didStart = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if didStart { url.stopAccessingSecurityScopedResource() }
    }
}

@MainActor
private final class ExactParentPanelDelegate: NSObject, NSOpenSavePanelDelegate {
    private let expected: URL

    init(expected: URL) { self.expected = expected.standardizedFileURL }

    func accepts(_ url: URL) -> Bool {
        url.isFileURL && (url.host == nil || url.host == "" || url.host == "localhost")
            && url.standardizedFileURL.path == expected.path
    }

    func panel(_ sender: Any, validate url: URL) throws {
        guard accepts(url) else {
            throw NSError(domain: "NamingAssistant.ParentAuthorization", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "请选择这一个精确文件夹：\(expected.path)。其他位置不会被授权。"])
        }
    }
}

private func localModelAvailabilityText(_ availability: LocalNameModelAvailability) -> String {
    switch availability {
    case .available: return "Apple 本机模型可用。"
    case .requiresMacOS26: return "本机模型需要 macOS 26 或以上；可使用本地词典。"
    case .frameworkUnavailable: return "此构建未包含本机模型框架；可使用本地词典。"
    case .deviceNotEligible: return "此 Mac 不支持 Apple 本机模型；可使用本地词典。"
    case .appleIntelligenceNotEnabled: return "Apple Intelligence 未启用；可使用本地词典。"
    case .modelNotReady: return "Apple 本机模型尚未就绪；可使用本地词典。"
    case .unavailable: return "Apple 本机模型暂不可用；可使用本地词典。"
    }
}
