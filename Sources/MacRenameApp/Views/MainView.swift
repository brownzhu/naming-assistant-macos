import SwiftUI
import MacRenameCore
import UniformTypeIdentifiers

struct MainView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            SearchReplaceBar(viewModel: viewModel)
                .padding()

            Divider()

            OptionsPanel(viewModel: viewModel)
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            if viewModel.items.isEmpty {
                DropZoneView(viewModel: viewModel)
            } else {
                FileListView(viewModel: viewModel)
            }

            Divider()

            StatusBar(viewModel: viewModel)
                .padding(.horizontal)
                .padding(.vertical, 8)
        }
        .navigationTitle("Quick Rename")
        .frame(minWidth: 700, idealWidth: 900, minHeight: 500, idealHeight: 650)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
            return true
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                if let url = try? await provider.loadItem(
                    forTypeIdentifier: UTType.fileURL.identifier
                ) as? Data {
                    if let fileURL = URL(dataRepresentation: url, relativeTo: nil) {
                        urls.append(fileURL)
                    }
                }
            }
            if !urls.isEmpty {
                viewModel.addFiles(urls: urls)
            }
        }
    }
}
