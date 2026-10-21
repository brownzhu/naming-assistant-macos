import SwiftUI
import MacRenameCore

struct FileListView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        Table(viewModel.items) {
            TableColumn("") { item in
                Toggle("", isOn: Binding(
                    get: { item.isSelected },
                    set: { viewModel.setSelected(item, $0) }
                ))
                .labelsHidden()
                .accessibilityLabel("Include \(item.originalName)")
            }
            .width(24)

            TableColumn("Original Name") { item in
                HStack(spacing: 4) {
                    Image(systemName: item.isFolder ? "folder.fill" : "doc.fill")
                        .foregroundStyle(item.isFolder ? .blue : .secondary)
                        .font(.system(size: 11))
                        .accessibilityHidden(true)
                    Text(item.originalName)
                        .lineLimit(1)
                }
                .padding(.leading, CGFloat(item.depth) * 16)
                .accessibilityLabel("\(item.isFolder ? "Folder" : "File"): \(item.originalName)")
            }

            TableColumn("New Name") { item in
                FileRowNewName(item: item)
            }

            TableColumn("Status") { item in
                StatusBadge(status: item.status)
            }
            .width(min: 60, ideal: 80, max: 100)
        }
    }
}

struct FileRowNewName: View {
    let item: RenameItem

    private var colorForStatus: Color {
        switch item.status {
        case .shouldRename, .renamed: return .primary
        default: return .red
        }
    }

    var body: some View {
        if let newName = item.newName {
            Text(newName)
                .lineLimit(1)
                .foregroundColor(colorForStatus)
                .accessibilityLabel("New name: \(newName)")
        } else {
            Text("—")
                .foregroundStyle(.quaternary)
                .accessibilityLabel("No change")
        }
    }
}

struct StatusBadge: View {
    let status: RenameStatus

    private struct Style {
        let title: String
        let icon: String
        let color: Color
        let help: String
    }

    private var style: Style? {
        switch status {
        case .shouldRename:
            return Style(title: "Rename", icon: "checkmark.circle", color: .blue,
                         help: "This row will be renamed when you click Rename.")
        case .renamed:
            return Style(title: "Renamed", icon: "checkmark.circle.fill", color: .green,
                         help: "Successfully renamed on disk. Use ⌘Z to undo.")
        case .invalidCharacters:
            return Style(title: "Invalid", icon: "xmark.circle.fill", color: .red,
                         help: "The new name is invalid: it contains '/' or ':', a control character, or a path-traversal component (\".\" or \"..\").")
        case .filenameTooLong:
            return Style(title: "Too long", icon: "xmark.circle.fill", color: .red,
                         help: "The new filename exceeds 255 bytes — the macOS limit for a single name component.")
        case .pathTooLong:
            return Style(title: "Too long", icon: "xmark.circle.fill", color: .red,
                         help: "The full path would exceed 1024 characters (PATH_MAX). Try a shorter name or move the parent folder closer to the volume root.")
        case .nameAlreadyExists:
            return Style(title: "Exists", icon: "exclamationmark.triangle.fill", color: .orange,
                         help: "Another file in this folder already has this name, or another row in this batch is renaming to the same name. Comparison is case-insensitive on APFS/HFS+.")
        case .excluded:
            return Style(title: "Excluded", icon: "minus.circle", color: .secondary,
                         help: "This row is unchecked or excluded by the current Filter options.")
        case .unchanged, .initial:
            return nil
        }
    }

    var body: some View {
        if let style {
            Label(style.title, systemImage: style.icon)
                .foregroundStyle(style.color)
                .font(.system(size: 11))
                .help(style.help)
        } else {
            Text("")
        }
    }
}
