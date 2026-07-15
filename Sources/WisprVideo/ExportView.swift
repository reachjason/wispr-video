import SwiftUI
import AppKit

struct ExportItem: Identifiable {
    let id = UUID()
    let label: String
    let ratio: String
    let dimensions: String
    var url: URL?
    var thumbnail: NSImage?
    var done = false
    var failed = false
}

final class ExportModel: ObservableObject {
    @Published var items: [ExportItem]
    @Published var processing = true
    let folder: URL

    init(items: [ExportItem], folder: URL) {
        self.items = items
        self.folder = folder
    }
}

struct ExportView: View {
    @ObservedObject var model: ExportModel

    private let columns = [GridItem(.flexible(), spacing: 16),
                           GridItem(.flexible(), spacing: 16)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(model.items) { item in
                        card(for: item)
                    }
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 620)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your clips are ready")
                    .font(.headline)
                Text(model.processing ? "Rendering social formats…" : "4 formats exported")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if model.processing {
                ProgressView().controlSize(.small)
            }
        }
        .padding(16)
    }

    private func card(for item: ExportItem) -> some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.85))
                if let thumb = item.thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else if item.failed {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundColor(.orange)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity)

            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(item.label) · \(item.ratio)")
                        .font(.subheadline).bold()
                    Text(item.dimensions)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    if let url = item.url {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .disabled(item.url == nil)
                .help("Reveal in Finder")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private var footer: some View {
        HStack {
            Button {
                NSWorkspace.shared.open(model.folder)
            } label: {
                Label("Open Folder", systemImage: "folder")
            }
            Spacer()
            Button("Done") {
                NSApp.keyWindow?.close()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }
}
