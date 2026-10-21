import SwiftUI

struct SearchReplaceBar: View {
    @Bindable var viewModel: AppViewModel

    enum Field: Hashable { case search, replace }
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                ClearableTextField(
                    placeholder: "Search for...",
                    text: $viewModel.searchTerm,
                    accessibilityLabel: "Search pattern",
                    clearAccessibilityLabel: "Clear search field"
                )
                .focused($focusedField, equals: .search)

                MRUMenu(
                    entries: viewModel.settings.searchMRU,
                    label: "Recent searches",
                    onSelect: { viewModel.searchTerm = $0 },
                    onClear: { viewModel.clearSearchMRU() }
                )

                Toggle("Aa", isOn: $viewModel.caseSensitive)
                    .toggleStyle(.button)
                    .help("Case sensitive")
                    .accessibilityLabel("Case sensitive")

                Toggle(".*", isOn: $viewModel.useRegex)
                    .toggleStyle(.button)
                    .help("Use regular expressions")
                    .accessibilityLabel("Regular expressions")

                Toggle("All", isOn: $viewModel.matchAll)
                    .toggleStyle(.button)
                    .help("Match all occurrences")
                    .accessibilityLabel("Match all occurrences")
            }

            HStack {
                Button {
                    viewModel.swapSearchAndReplace()
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Swap search and replace (⌥⌘L)")
                .accessibilityLabel("Swap search and replace")

                ClearableTextField(
                    placeholder: "Replace with...",
                    text: $viewModel.replaceTerm,
                    accessibilityLabel: "Replacement pattern",
                    clearAccessibilityLabel: "Clear replace field"
                )
                .focused($focusedField, equals: .replace)

                MRUMenu(
                    entries: viewModel.settings.replaceMRU,
                    label: "Recent replacements",
                    onSelect: { viewModel.replaceTerm = $0 },
                    onClear: { viewModel.clearReplaceMRU() }
                )

                TokenMenu(viewModel: viewModel)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickRenameFocusSearch)) { _ in
            focusedField = .search
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickRenameFocusReplace)) { _ in
            focusedField = .replace
        }
    }
}

/// A `TextField` with a trailing clear button (visible while non-empty)
/// and Esc-to-clear when focused. Esc with an empty field is left alone
/// so other handlers (sheet dismiss, etc.) still receive it.
struct ClearableTextField: View {
    let placeholder: String
    @Binding var text: String
    let accessibilityLabel: String
    let clearAccessibilityLabel: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel(accessibilityLabel)
            .overlay(alignment: .trailing) {
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 6)
                    .help("Clear (Esc)")
                    .accessibilityLabel(clearAccessibilityLabel)
                }
            }
            .onKeyPress(.escape) {
                if text.isEmpty { return .ignored }
                text = ""
                return .handled
            }
    }
}

struct TokenMenu: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        Menu {
            Section("Enumeration") {
                Button("Counter ${start=1,increment=1,padding=3}") {
                    insertToken("${start=1,increment=1,padding=3}")
                }
            }
            Section("Random") {
                Button("Random alphanumeric ${rstringalnum=8}") {
                    insertToken("${rstringalnum=8}")
                }
                Button("Random letters ${rstringalpha=8}") {
                    insertToken("${rstringalpha=8}")
                }
                Button("Random digits ${rstringdigit=4}") {
                    insertToken("${rstringdigit=4}")
                }
                Button("UUID ${ruuidv4}") {
                    insertToken("${ruuidv4}")
                }
            }
            Section("Date / Time") {
                Button("Year $YYYY") { insertToken("$YYYY") }
                Button("Month $MM") { insertToken("$MM") }
                Button("Day $DD") { insertToken("$DD") }
                Button("Hour (24h) $HH") { insertToken("$HH") }
                Button("Minute $mm") { insertToken("$mm") }
                Button("Second $ss") { insertToken("$ss") }
                Button("Full date $YYYY-$MM-$DD") { insertToken("$YYYY-$MM-$DD") }
                Button("Full datetime $YYYY-$MM-$DD_$HH-$mm-$ss") {
                    insertToken("$YYYY-$MM-$DD_$HH-$mm-$ss")
                }
            }
            Section("Metadata (EXIF)") {
                Button("Camera make $CAMERA_MAKE") { insertToken("$CAMERA_MAKE") }
                Button("Camera model $CAMERA_MODEL") { insertToken("$CAMERA_MODEL") }
                Button("ISO $ISO") { insertToken("$ISO") }
                Button("Aperture $APERTURE") { insertToken("$APERTURE") }
                Button("Date taken $DATE_TAKEN_YYYY-$DATE_TAKEN_MM-$DATE_TAKEN_DD") {
                    insertToken("$DATE_TAKEN_YYYY-$DATE_TAKEN_MM-$DATE_TAKEN_DD")
                }
            }
        } label: {
            Image(systemName: "ellipsis.curlybraces")
        }
        .help("Insert token")
    }

    private func insertToken(_ token: String) {
        viewModel.replaceTerm += token
    }
}

struct MRUMenu: View {
    let entries: [String]
    let label: String
    let onSelect: (String) -> Void
    let onClear: () -> Void

    var body: some View {
        Menu {
            if entries.isEmpty {
                Text("No recent entries").foregroundStyle(.secondary)
            } else {
                ForEach(entries, id: \.self) { entry in
                    Button(entry) { onSelect(entry) }
                }
                Divider()
                Button("Clear Recent", role: .destructive) { onClear() }
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .help(label)
        .disabled(entries.isEmpty)
        .accessibilityLabel(label)
    }
}
