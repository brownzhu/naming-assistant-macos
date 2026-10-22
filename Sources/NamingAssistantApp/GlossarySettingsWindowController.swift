import AppKit
import MacRenameCore

@MainActor
final class GlossarySettingsWindowController: NSWindowController {
    private let editor = NSTextView()
    private let status = NSTextField(wrappingLabelWithString: "只保存在本机；不会上传，也不调用模型。")
    private let onSave: () -> Void

    init(onSave: @escaping () -> Void) {
        self.onSave = onSave
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "词语转换词典"
        window.minSize = NSSize(width: 620, height: 500)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildInterface()
        populate(NamingPreferencesStore.glossary())
        window.center()
    }
    required init?(coder: NSCoder) { nil }

    private func buildInterface() {
        guard let content = window?.contentView else { return }
        let help = NSTextField(wrappingLabelWithString: "每行一条：原词 = english_snake_case\n可以新增、修改或删除内置词。最多 100 条；删除的转换不再使用。未知文字需要手动填写。")
        help.font = .systemFont(ofSize: 13)
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        editor.textContainerInset = NSSize(width: 12, height: 12)
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 680, height: 400))
        editor.frame = scroll.contentView.bounds
        editor.minSize = NSSize(width: 0, height: 260)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = editor
        let reset = NSButton(title: "恢复内置词典", target: self, action: #selector(reset(_:)))
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancel(_:)))
        let save = NSButton(title: "保存词典", target: self, action: #selector(save(_:)))
        save.bezelStyle = .rounded
        let buttons = NSStackView(views: [reset, cancel, save])
        buttons.spacing = 12
        let stack = NSStackView(views: [help, scroll, status, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 260),
            help.widthAnchor.constraint(equalTo: stack.widthAnchor),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func populate(_ preferences: NameGlossaryPreferences) {
        editor.string = preferences.entries.map { $0.source + " = " + $0.target }.joined(separator: "\n")
    }
    @objc private func reset(_ sender: Any?) { populate(.standard); status.stringValue = "已载入内置词典；点击保存才生效。" }
    @objc private func cancel(_ sender: Any?) { close() }
    @objc private func save(_ sender: Any?) {
        do {
            guard editor.string.utf8.count <= 50_000 else { throw EditError.invalid("词典文本过长。") }
            var entries: [NameGlossaryEntry] = []
            for (index, line) in editor.string.components(separatedBy: .newlines).enumerated() {
                if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                let parts = line.components(separatedBy: "=")
                guard parts.count == 2 else { throw EditError.invalid("第 \(index + 1) 行请使用：原词 = english_snake_case") }
                entries.append(NameGlossaryEntry(source: parts[0].trimmingCharacters(in: .whitespaces), target: parts[1].trimmingCharacters(in: .whitespaces)))
            }
            try NamingPreferencesStore.save(NameGlossaryPreferences(entries: entries))
            onSave()
            close()
        } catch { status.stringValue = error.localizedDescription }
    }
    private enum EditError: LocalizedError {
        case invalid(String)
        var errorDescription: String? { switch self { case .invalid(let text): return text } }
    }
}
