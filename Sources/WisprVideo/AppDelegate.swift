import AppKit
import AVFoundation
import SwiftUI
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum State { case idle, countingDown, recording }

    private var statusItem: NSStatusItem!
    private var toggleMenuItem: NSMenuItem!

    private let recorder = CameraRecorder()
    private let hotKey = HotKey()

    private var recorderPanel: RecorderPanel?
    private var exportWindow: NSWindow?

    private var state: State = .idle

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        recorder.onFinish = { [weak self] url in self?.handleFinished(url) }
        hotKey.onKeyDown = { [weak self] in self?.toggle() }
        hotKey.register(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | optionKey))
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        toggleMenuItem = NSMenuItem(title: "Start Recording  (⌥⌘V)",
                                    action: #selector(menuToggle),
                                    keyEquivalent: "")
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Wispr Video", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu

        updateStatusIcon()
    }

    private func updateStatusIcon() {
        let active = state != .idle
        let name = active ? "video.fill" : "video"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Wispr Video")
        image?.isTemplate = !active
        statusItem.button?.image = image
        statusItem.button?.contentTintColor = active ? .systemRed : nil
        toggleMenuItem.title = active ? "Stop Recording  (⌥⌘V)" : "Start Recording  (⌥⌘V)"
    }

    @objc private func menuToggle() { toggle() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Recording control

    private func toggle() {
        if state == .idle { start() } else { stop() }
    }

    private func start() {
        ensurePermissions { [weak self] granted in
            guard let self else { return }
            guard granted else { self.showPermissionAlert(); return }
            guard self.recorder.configureIfNeeded() else {
                self.showAlert(title: "No camera found",
                               message: "Wispr Video couldn't find a camera to record from.")
                return
            }
            self.state = .countingDown
            self.updateStatusIcon()
            self.recorder.startPreview()
            self.showRecorderPanel()
            self.recorderPanel?.runCountdown(from: 3) { [weak self] in
                guard let self, self.state == .countingDown else { return }
                self.state = .recording
                self.updateStatusIcon()
                self.recorder.beginRecording()
                self.recorderPanel?.startTimer()
            }
        }
    }

    private func stop() {
        switch state {
        case .countingDown:
            // Cancel before any file was written — discard cleanly.
            cancelCapture()
        case .recording:
            recorder.stop()   // handleFinished() continues the flow
        case .idle:
            break
        }
    }

    private func cancelCapture() {
        state = .idle
        updateStatusIcon()
        closeRecorderPanel()
        recorder.teardownSession()
    }

    private func handleFinished(_ url: URL?) {
        state = .idle
        updateStatusIcon()
        closeRecorderPanel()
        recorder.teardownSession()

        guard let url else {
            showAlert(title: "Recording failed",
                      message: "Something went wrong while capturing the video.")
            return
        }
        presentExportChooser(masterURL: url)
    }

    private func closeRecorderPanel() {
        recorderPanel?.teardown()
        recorderPanel?.close()
        recorderPanel = nil
    }

    // MARK: - Recorder panel

    private func showRecorderPanel() {
        let panel = RecorderPanel(previewLayer: recorder.previewLayer)
        panel.onStop = { [weak self] in self?.stop() }
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        recorderPanel = panel
    }

    // MARK: - Export

    /// Saves the raw original, then shows the format picker.
    private func presentExportChooser(masterURL: URL) {
        let folder = makeOutputFolder()
        let rawURL = folder.appendingPathComponent("raw-original.mov")
        try? FileManager.default.moveItem(at: masterURL, to: rawURL)

        let model = ExportModel(specs: VideoExporter.specs,
                                folder: folder,
                                rawURL: rawURL,
                                defaultSelected: ["vertical-9x16"])
        model.onExport = { [weak self] chosen in
            self?.runExport(specs: chosen, source: rawURL, model: model)
        }
        showExportWindow(model: model)
    }

    private func runExport(specs: [ExportSpec], source: URL, model: ExportModel) {
        model.items = specs.map {
            ExportItem(label: $0.label, ratio: $0.ratio, platforms: $0.platforms,
                       dimensions: "\($0.width) × \($0.height)")
        }

        Task { @MainActor in
            for (index, spec) in specs.enumerated() {
                do {
                    let out = try await VideoExporter.export(source: source, spec: spec, outputDir: model.folder)
                    model.items[index].url = out
                    model.items[index].thumbnail = VideoExporter.thumbnail(for: out)
                    model.items[index].done = true
                } catch {
                    model.items[index].failed = true
                }
            }
            model.phase = .done
        }
    }

    private func showExportWindow(model: ExportModel) {
        let hosting = NSHostingController(rootView: ExportView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Wispr Video"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        exportWindow = window
    }

    private func makeOutputFolder() -> URL {
        let base = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let folder = base
            .appendingPathComponent("WisprVideo", isDirectory: true)
            .appendingPathComponent(formatter.string(from: Date()), isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    // MARK: - Permissions

    private func ensurePermissions(completion: @escaping (Bool) -> Void) {
        requestAccess(for: .video) { videoOK in
            self.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async { completion(videoOK) }
            }
        }
    }

    private func requestAccess(for type: AVMediaType, completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: type) { completion($0) }
        default:
            completion(false)
        }
    }

    // MARK: - Alerts

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Camera access needed"
        alert.informativeText = "Enable camera (and microphone) access for Wispr Video in System Settings › Privacy & Security."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
