import AppKit
import AVFoundation
import SwiftUI
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var toggleMenuItem: NSMenuItem!

    private let recorder = CameraRecorder()
    private let hotKey = HotKey()

    private var recorderPanel: RecorderPanel?
    private var exportWindow: NSWindow?

    private var recording = false

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
        let name = recording ? "video.fill" : "video"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Wispr Video")
        image?.isTemplate = !recording
        statusItem.button?.image = image
        statusItem.button?.contentTintColor = recording ? .systemRed : nil
        toggleMenuItem.title = recording ? "Stop Recording  (⌥⌘V)" : "Start Recording  (⌥⌘V)"
    }

    @objc private func menuToggle() { toggle() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Recording control

    private func toggle() {
        if recording { stop() } else { start() }
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
            self.recording = true
            self.updateStatusIcon()
            self.showRecorderPanel()
            self.recorder.begin()
        }
    }

    private func stop() {
        guard recording else { return }
        recorder.stop()   // handleFinished() continues the flow
    }

    private func handleFinished(_ url: URL?) {
        recording = false
        updateStatusIcon()

        recorderPanel?.teardown()
        recorderPanel?.close()
        recorderPanel = nil
        recorder.teardownSession()

        guard let url else {
            showAlert(title: "Recording failed",
                      message: "Something went wrong while capturing the video.")
            return
        }
        startExport(source: url)
    }

    // MARK: - Recorder panel

    private func showRecorderPanel() {
        let panel = RecorderPanel(previewLayer: recorder.previewLayer)
        panel.onStop = { [weak self] in self?.stop() }
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        panel.startTimer()
        NSApp.activate(ignoringOtherApps: true)
        recorderPanel = panel
    }

    // MARK: - Export

    private func startExport(source: URL) {
        let folder = makeOutputFolder()
        let items = VideoExporter.specs.map {
            ExportItem(label: $0.label, ratio: $0.ratio,
                       dimensions: "\($0.width) × \($0.height)")
        }
        let model = ExportModel(items: items, folder: folder)
        showExportWindow(model: model)

        Task { @MainActor in
            for (index, spec) in VideoExporter.specs.enumerated() {
                do {
                    let out = try await VideoExporter.export(source: source, spec: spec, outputDir: folder)
                    let thumb = VideoExporter.thumbnail(for: out)
                    model.items[index].url = out
                    model.items[index].thumbnail = thumb
                    model.items[index].done = true
                } catch {
                    model.items[index].failed = true
                }
            }
            model.processing = false
            try? FileManager.default.removeItem(at: source)
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
                // Audio is nice-to-have; gate only on camera.
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
