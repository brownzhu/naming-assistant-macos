import AppKit
import MacRenameCore

/// Edits an in-memory copy. The owner persists only the validated save result.
@MainActor
final class CategoryPreferencesWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSTextViewDelegate {
    private var draft: NamingCategoryPreferences
    private let onSave: (NamingCategoryPreferences) throws -> Void
    private let table = NSTableView()
    private let labelField = NSTextField(string: "")
    private let tokenField = NSTextField(string: "")
    private let keywordsView = NSTextView()
    private let defaultPopup = NSPopUpButton()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let addButton = NSButton(title: "添加", target: nil, action: nil)
    private let removeButton = NSButton(title: "删除", target: nil, action: nil)
    private let upButton = NSButton(title: "上移", target: nil, action: nil)
    private let downButton = NSButton(title: "下移", target: nil, action: nil)
    private var loadingEditor = false

    init(preferences: NamingCategoryPreferences, onSave: @escaping (NamingCategoryPreferences) throws -> Void) {
        draft = preferences
        self.onSave = onSave
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 720),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "编辑分类与推荐词"
        window.minSize = NSSize(width: 760, height: 680)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildInterface()
        reload(selecting: draft.options.isEmpty ? nil : 0)
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    private var selectedIndex: Int? {
        draft.options.indices.contains(table.selectedRow) ? table.selectedRow : nil
    }

    private func buildInterface() {
        guard let content = window?.contentView else { return }
        let title = NSTextField(labelWithString: "决定卡片显示哪些分类")
        title.font = .systemFont(ofSize: 21, weight: .semibold)
        let introduction = label("勾选需要显示的分类，并调整顺序。选中一行可修改中文名称、英文标记和推荐关键词。")
        introduction.maximumNumberOfLines = 2

        let visibleColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("visible"))
        visibleColumn.title = "显示"
        visibleColumn.width = 54
        visibleColumn.minWidth = 54
        visibleColumn.maxWidth = 54
        let labelColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("label"))
        labelColumn.title = "中文名称"
        labelColumn.width = 250
        labelColumn.minWidth = 150
        let tokenColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("token"))
        tokenColumn.title = "英文标记（用于文件名）"
        tokenColumn.width = 360
        tokenColumn.minWidth = 200
        [visibleColumn, labelColumn, tokenColumn].forEach(table.addTableColumn)
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 28
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        let list = NSScrollView()
        list.documentView = table
        list.hasVerticalScroller = true
        list.borderType = .bezelBorder
        list.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        let listHeight = list.heightAnchor.constraint(equalToConstant: 170)
        listHeight.priority = .defaultLow
        listHeight.isActive = true

        configure(addButton, action: #selector(addCategory(_:)))
        configure(removeButton, action: #selector(removeCategory(_:)))
        configure(upButton, action: #selector(moveCategoryUp(_:)))
        configure(downButton, action: #selector(moveCategoryDown(_:)))
        let restore = NSButton(title: "恢复五个默认分类", target: self, action: #selector(restoreDefaults(_:)))
        restore.bezelStyle = .rounded
        let toolbar = NSStackView(views: [addButton, removeButton, upButton, downButton, restore])
        toolbar.spacing = 8

        labelField.delegate = self
        tokenField.delegate = self
        labelField.placeholderString = "例如 科研"
        tokenField.placeholderString = "例如 research 或 client_work"
        tokenField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "中文名称"), labelField],
            [NSTextField(labelWithString: "英文标记"), tokenField],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        let keywordsLabel = label("推荐关键词（逗号或换行分隔，可含中英文；每类最多 30 个）")
        keywordsLabel.font = .systemFont(ofSize: 12)
        keywordsLabel.textColor = .secondaryLabelColor
        keywordsView.isRichText = false
        keywordsView.importsGraphics = false
        keywordsView.isAutomaticQuoteSubstitutionEnabled = false
        keywordsView.isAutomaticDashSubstitutionEnabled = false
        keywordsView.isAutomaticTextReplacementEnabled = false
        keywordsView.font = .systemFont(ofSize: 13)
        keywordsView.textContainerInset = NSSize(width: 6, height: 6)
        keywordsView.isHorizontallyResizable = false
        keywordsView.isVerticallyResizable = true
        keywordsView.autoresizingMask = [.width]
        keywordsView.minSize = NSSize(width: 0, height: 64)
        keywordsView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        keywordsView.textContainer?.widthTracksTextView = true
        keywordsView.delegate = self
        let keywordsScroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 700, height: 64))
        keywordsView.frame = keywordsScroll.contentView.bounds
        keywordsScroll.documentView = keywordsView
        keywordsScroll.hasVerticalScroller = true
        keywordsScroll.borderType = .bezelBorder
        keywordsScroll.heightAnchor.constraint(equalToConstant: 64).isActive = true

        defaultPopup.target = self
        defaultPopup.action = #selector(changeDefault(_:))
        let defaultRow = NSStackView(views: [NSTextField(labelWithString: "没有明确线索时默认选中"), defaultPopup])
        defaultRow.spacing = 12
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.maximumNumberOfLines = 2
        status.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelEditing(_:)))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "保存分类设置", target: self, action: #selector(savePreferences(_:)))
        save.bezelStyle = .rounded
        let footer = NSStackView(views: [cancel, save])
        footer.spacing = 12

        let stack = NSStackView(views: [title, introduction, list, toolbar, grid, keywordsLabel, keywordsScroll, defaultRow, status, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
        for view in [introduction, list, grid, keywordsLabel, keywordsScroll, status] as [NSView] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        footer.setContentHuggingPriority(.required, for: .vertical)
        list.setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: 13)
        return field
    }

    private func configure(_ button: NSButton, action: Selector) {
        button.target = self
        button.action = action
        button.bezelStyle = .rounded
    }

    func numberOfRows(in tableView: NSTableView) -> Int { draft.options.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard draft.options.indices.contains(row) else { return nil }
        let option = draft.options[row]
        if tableColumn?.identifier.rawValue == "visible" {
            let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleVisibility(_:)))
            button.tag = row
            button.state = option.isVisible ? .on : .off
            button.setAccessibilityLabel("显示“" + option.label + "”分类")
            let cell = NSView()
            button.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(button)
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                button.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }
        let field = NSTextField(labelWithString: tableColumn?.identifier.rawValue == "label" ? option.label : option.token)
        field.lineBreakMode = .byTruncatingTail
        field.isSelectable = false
        if tableColumn?.identifier.rawValue == "token" { field.font = .monospacedSystemFont(ofSize: 12, weight: .regular) }
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) { loadEditor() }

    func controlTextDidChange(_ obj: Notification) { updateDraftFromEditor() }
    func textDidChange(_ notification: Notification) { updateDraftFromEditor() }

    private func loadEditor() {
        loadingEditor = true
        defer { loadingEditor = false }
        let option = selectedIndex.map { draft.options[$0] }
        labelField.stringValue = option?.label ?? ""
        tokenField.stringValue = option?.token ?? ""
        keywordsView.string = option?.keywords.joined(separator: ", ") ?? ""
        labelField.isEnabled = option != nil
        tokenField.isEnabled = option != nil
        keywordsView.isEditable = option != nil
        updateControls()
    }

    private func updateDraftFromEditor() {
        guard !loadingEditor, let index = selectedIndex else { return }
        draft.options[index].label = labelField.stringValue
        draft.options[index].token = tokenField.stringValue
        draft.options[index].keywords = keywordsView.string.components(separatedBy: CharacterSet(charactersIn: ",，\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        table.reloadData(forRowIndexes: IndexSet(integer: index), columnIndexes: IndexSet(integersIn: 1..<3))
        updateControls()
    }

    private func reload(selecting index: Int?) {
        loadingEditor = true
        table.reloadData()
        if let index, draft.options.indices.contains(index) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            table.scrollRowToVisible(index)
        } else { table.deselectAll(nil) }
        loadingEditor = false
        loadEditor()
    }

    private func updateControls() {
        addButton.isEnabled = draft.options.count < 20
        removeButton.isEnabled = selectedIndex != nil && draft.options.count > 1
        upButton.isEnabled = (selectedIndex ?? 0) > 0
        downButton.isEnabled = selectedIndex.map { $0 + 1 < draft.options.count } ?? false
        let visible = draft.visibleOptions
        if !visible.contains(where: { $0.id == draft.defaultID }), let first = visible.first { draft.defaultID = first.id }
        defaultPopup.removeAllItems()
        for option in visible {
            defaultPopup.addItem(withTitle: (option.label.isEmpty ? "未填写名称" : option.label) + " · " + option.token)
            defaultPopup.lastItem?.representedObject = option.id
        }
        if let index = visible.firstIndex(where: { $0.id == draft.defaultID }) { defaultPopup.selectItem(at: index) }
        defaultPopup.isEnabled = !visible.isEmpty
        showStatus("卡片将显示 \(visible.count) 个分类，已配置 \(draft.options.count)/20 个。推荐只使用名字和这里的关键词；点击保存后生效。")
    }

    private func showStatus(_ text: String, error: Bool = false) {
        status.stringValue = text
        status.textColor = error ? .systemRed : .secondaryLabelColor
    }

    @objc private func toggleVisibility(_ sender: NSButton) {
        guard draft.options.indices.contains(sender.tag) else { return }
        window?.makeFirstResponder(nil)
        updateDraftFromEditor()
        let index = sender.tag
        if sender.state != .on, draft.options[index].isVisible, draft.visibleOptions.count <= 1 {
            sender.state = .on
            showStatus("至少保留一个显示的分类。请先启用其他分类，再隐藏这一项。", error: true)
            return
        }
        draft.options[index].isVisible = sender.state == .on
        reload(selecting: index)
    }

    @objc private func addCategory(_ sender: Any?) {
        window?.makeFirstResponder(nil)
        updateDraftFromEditor()
        guard draft.options.count < 20 else { showStatus("最多配置 20 个分类。", error: true); return }
        let tokens = Set(draft.options.map(\.token))
        var number = 1
        while tokens.contains("custom_\(number)") { number += 1 }
        draft.options.append(NamingCategoryOption(id: UUID().uuidString.lowercased(), label: "新分类", token: "custom_\(number)", keywords: [], isVisible: true))
        reload(selecting: draft.options.count - 1)
        window?.makeFirstResponder(labelField)
        labelField.selectText(nil)
    }

    @objc private func removeCategory(_ sender: Any?) {
        window?.makeFirstResponder(nil)
        updateDraftFromEditor()
        guard let index = selectedIndex, draft.options.count > 1 else { return }
        guard !draft.options[index].isVisible || draft.visibleOptions.count > 1 else {
            showStatus("至少保留一个显示的分类。请先启用其他分类，再删除这一项。", error: true)
            return
        }
        draft.options.remove(at: index)
        reload(selecting: min(index, draft.options.count - 1))
    }

    @objc private func moveCategoryUp(_ sender: Any?) { moveSelection(by: -1) }
    @objc private func moveCategoryDown(_ sender: Any?) { moveSelection(by: 1) }

    private func moveSelection(by offset: Int) {
        window?.makeFirstResponder(nil)
        updateDraftFromEditor()
        guard let index = selectedIndex, draft.options.indices.contains(index + offset) else { return }
        draft.options.swapAt(index, index + offset)
        reload(selecting: index + offset)
    }

    @objc private func restoreDefaults(_ sender: Any?) {
        window?.makeFirstResponder(nil)
        draft = .standard
        reload(selecting: 0)
    }

    @objc private func changeDefault(_ sender: Any?) {
        guard let id = defaultPopup.selectedItem?.representedObject as? String,
              draft.visibleOptions.contains(where: { $0.id == id }) else { return }
        draft.defaultID = id
        updateControls()
    }

    @objc private func savePreferences(_ sender: Any?) {
        window?.makeFirstResponder(nil)
        updateDraftFromEditor()
        do {
            let preferences = try draft.validated()
            try onSave(preferences)
            close()
        } catch { showStatus(error.localizedDescription, error: true) }
    }

    @objc private func cancelEditing(_ sender: Any?) { close() }
}
