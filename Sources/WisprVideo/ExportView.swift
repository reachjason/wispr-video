import SwiftUI
import AppKit

struct ExportItem: Identifiable {
    let id = UUID()
    let label: String
    let ratio: String
    let platforms: String
    let dimensions: String
    var url: URL?
    var thumbnail: NSImage?
    var done = false
    var failed = false
}

final class ExportModel: ObservableObject {
    enum Phase { case choosing, working, done }

    let specs: [ExportSpec]
    let folder: URL
    let rawURL: URL

    @Published var phase: Phase = .choosing
    @Published var selected: Set<String>   // keyed by spec.fileName
    @Published var items: [ExportItem] = []

    /// Set by the app; invoked with the chosen specs when the user taps Export.
    var onExport: (([ExportSpec]) -> Void)?

    init(specs: [ExportSpec], folder: URL, rawURL: URL, defaultSelected: Set<String>) {
        self.specs = specs
        self.folder = folder
        self.rawURL = rawURL
        self.selected = defaultSelected
    }
}

struct ExportView: View {
    @ObservedObject var model: ExportModel

    var body: some View {
        switch model.phase {
        case .choosing:
            ChooseFormatsView(model: model)
        case .working, .done:
            ResultsView(model: model)
        }
    }
}

// MARK: - Choose formats

private struct ChooseFormatsView: View {
    @ObservedObject var model: ExportModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Choose formats to export")
                    .font(.headline)
                Text("Only the formats you pick are saved. The raw original is always kept.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.specs, id: \.fileName) { spec in
                        row(for: spec)
                    }
                }
                .padding(16)
            }

            Divider()

            HStack {
                Button("Cancel") { NSApp.keyWindow?.close() }
                Spacer()
                Button("Export Selected") {
                    let chosen = model.specs.filter { model.selected.contains($0.fileName) }
                    model.phase = .working
                    model.onExport?(chosen)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.selected.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 460, height: 420)
    }

    private func row(for spec: ExportSpec) -> some View {
        let isOn = Binding(
            get: { model.selected.contains(spec.fileName) },
            set: { on in
                if on { model.selected.insert(spec.fileName) }
                else { model.selected.remove(spec.fileName) }
            }
        )
        return Toggle(isOn: isOn) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(spec.platforms)
                        .font(.body).bold()
                    Text("\(spec.label) · \(spec.ratio) · \(spec.width) × \(spec.height)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .toggleStyle(.checkbox)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

// MARK: - Results

private struct ResultsView: View {
    @ObservedObject var model: ExportModel

    private let columns = [GridItem(.flexible(), spacing: 16),
                           GridItem(.flexible(), spacing: 16)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.phase == .done ? "Your clips are ready" : "Rendering…")
                        .font(.headline)
                    Text(model.phase == .done
                         ? "\(model.items.count) format\(model.items.count == 1 ? "" : "s") exported"
                         : "Rendering selected formats…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if model.phase == .working {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(16)

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

            HStack {
                Button {
                    NSWorkspace.shared.open(model.folder)
                } label: {
                    Label("Open Folder", systemImage: "folder")
                }
                Spacer()
                Button("Done") { NSApp.keyWindow?.close() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 560, height: 620)
    }

    private func card(for item: ExportItem) -> some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.85))
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
                    Text(item.platforms)
                        .font(.subheadline).bold()
                    Text("\(item.label) · \(item.ratio) · \(item.dimensions)")
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
}
