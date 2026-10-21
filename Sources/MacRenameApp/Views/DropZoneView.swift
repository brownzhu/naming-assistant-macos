import SwiftUI

struct DropZoneView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text("Drop files or folders here")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("or")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Button("Choose Files...") {
                viewModel.openFilePanel()
            }
            .buttonStyle(.bordered)
            .help("Open files or a folder to rename (⌘O)")

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Drop zone. Drop files or folders here, or use the Choose Files button.")
    }
}
