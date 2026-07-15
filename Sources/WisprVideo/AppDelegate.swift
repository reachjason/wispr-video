import AppKit
import AVFoundation
import SwiftUI
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum State { case idle, countingDown, recording }
    private enum Mode { case webcam, loom }

    private var statusItem: NSStatusItem!
    private var webcamItem: NSMenuItem!
    private var loomItem: NSMenuItem!
    private var bubbleMenu: NSMenu!

    private let webcam = CameraRecorder()
    private let loom = LoomRecorder()

    private var recorderPanel: RecorderPanel?
    private var exportWindow: NSWindow?

    private var state: State = .idle
    private var mode: Mode = .webcam

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        webcam.onFinish = { [weak self] url in self?.handleFinished(url) }
        loom.onFinish = { [weak self] url in self?.handleFinished(url) }

        HotKeyCenter.shared.register(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | optionKey)) {
            [weak self] in self?.toggle(.webcam)
        }
        HotKeyCenter.shared.register(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(cmdKey | optionKey)) {
            [weak self] in self?.toggle(.loom)
        }
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.autoenablesItems = false

        webcamItem = NSMenuItem(title: "Record Webcam  (⌥⌘V)", action: #selector(webcamToggle), keyEquivalent: "")
        webcamItem.target = self
        menu.addItem(webcamItem)

        loomItem = NSMenuItem(title: "Record Loom — Screen + Camera  (⌥⌘L)", action: #selector(loomToggle), keyEquivalent: "")
        loomItem.target = self
        menu.addItem(loomItem)

        menu.addItem(.separator())

        bubbleMenu = NSMenu()
        for corner in BubbleCorner.allCases {
            let item = NSMenuItem(title: corner.title, action: #selector(selectBubbleCorner(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = corner.rawValue
            item.state = (corner == Settings.bubbleCorner) ? .on : .off
            bubbleMenu.addItem(item)
        }
        let bubbleParent = NSMenuItem(title: "Loom Camera Bubble", action: nil, keyEquivalent: "")
        bubbleParent.submenu = bubbleMenu
        menu.addItem(bubbleParent)

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

        webcamItem.title = (active && mode == .webcam) ? "Stop Recording  (⌥⌘V)" : "Record Webcam  (⌥⌘V)"
        loomItem.title = (active && mode == .loom)
            ? "Stop Recording  (⌥⌘L)" : "Record Loom — Screen + Camera  (⌥⌘L)"
        webcamItem.isEnabled = !active || mode == .webcam
        loomItem.isEnabled = !active || mode == .loom
    }

    @objc private func webcamToggle() { toggle(.webcam) }
    @objc private func loomToggle() { toggle(.loom) }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func selectBubbleCorner(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let corner = BubbleCorner(rawValue: raw) else { return }
        Settings.bubbleCorner = corner
        for item in bubbleMenu.items {
            item.state = ((item.representedObject as? String) == raw) ? .on : .off
        }
    }

    // MARK: - Recording control

    private func toggle(_ requested: Mode) {
        switch state {
        case .idle:
            mode = requested
            requested == .webcam ? startWebcam() : startLoom()
        case .countingDown, .recording:
            if mode == requested { stop() }   // otherwise busy in the other mode — ignore
        }
    }

    private func stop() {
        switch state {
        case .countingDown:
            cancelCapture()
        case .recording:
            (mode == .webcam ? webcam.stop() : loom.stop())   // handleFinished() continues
        case .idle:
            break
        }
    }

    private func cancelCapture() {
        state = .idle
        updateStatusIcon()
        closeRecorderPanel()
        if mode == .webcam { webcam.teardownSession() } else { loom.cancelPreview() }
    }

    // MARK: - Webcam mode

    private func startWebcam() {
        ensurePermissions { [weak self] granted in
            guard let self else { return }
            guard granted else { self.showPermissionAlert(); return }
            guard self.webcam.configureIfNeeded() else {
                self.showAlert(title: "No camera found",
                               message: "Wispr Video couldn't find a camera to record from.")
                return
            }
            self.state = .countingDown
            self.updateStatusIcon()
            self.webcam.startPreview()
            self.showRecorderPanel(previewLayer: self.webcam.previewLayer)
            self.recorderPanel?.runCountdown(from: 3) { [weak self] in
                guard let self, self.state == .countingDown else { return }
                self.state = .recording
                self.updateStatusIcon()
                self.webcam.beginRecording()
                self.recorderPanel?.startTimer()
            }
        }
    }

    // MARK: - Loom mode

    private func startLoom() {
        ensurePermissions { [weak self] granted in
            guard let self else { return }
            guard granted else { self.showPermissionAlert(); return }
            guard self.loom.configureCameraAndMic() else {
                self.showAlert(title: "No camera found",
                               message: "Wispr Video couldn't find a camera to record from.")
                return
            }
            Task { @MainActor in
                do {
                    try await self.loom.prepareScreen()
                } catch {
                    self.showScreenPermissionAlert()
                    return
                }
                self.state = .countingDown
                self.updateStatusIcon()
                self.loom.startPreview()
                self.showRecorderPanel(previewLayer: self.loom.previewLayer)
                self.recorderPanel?.runCountdown(from: 3) { [weak self] in
                    guard let self, self.state == .countingDown else { return }
                    self.state = .recording
                    self.updateStatusIcon()
                    Task { @MainActor in
                        do { try await self.loom.beginCapture() }
                        catch {
                            self.showAlert(title: "Couldn't start screen recording",
                                           message: error.localizedDescription)
                            self.handleFinished(nil)
                            return
                        }
                        self.recorderPanel?.startTimer()
                    }
                }
            }
        }
    }

    // MARK: - Finish

    private func handleFinished(_ url: URL?) {
        let finishedMode = mode
        state = .idle
        updateStatusIcon()
        closeRecorderPanel()
        if finishedMode == .webcam { webcam.teardownSession() }

        guard let url else {
            showAlert(title: "Recording failed",
                      message: "Something went wrong while capturing the video.")
            return
        }
        presentExportChooser(masterURL: url, screenSource: finishedMode == .loom)
    }

    // MARK: - Recorder panel

    private func showRecorderPanel(previewLayer: CALayer) {
        let panel = RecorderPanel(previewLayer: previewLayer)
        panel.onStop = { [weak self] in self?.stop() }
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        recorderPanel = panel
    }

    private func closeRecorderPanel() {
        recorderPanel?.teardown()
        recorderPanel?.close()
        recorderPanel = nil
    }

    // MARK: - Export

    private func presentExportChooser(masterURL: URL, screenSource: Bool) {
        let folder = makeOutputFolder()
        let rawURL = folder.appendingPathComponent("raw-original.mov")
        try? FileManager.default.moveItem(at: masterURL, to: rawURL)

        let defaultRatio = screenSource ? "16:9" : "9:16"
        let defaultSelected = Set(VideoExporter.specs.filter { $0.ratio == defaultRatio }.map(\.fileName))
        let note = screenSource
            ? "Tip: screen recordings are landscape — non-16:9 formats will center-crop your screen."
            : nil

        let model = ExportModel(specs: VideoExporter.specs,
                                folder: folder,
                                rawURL: rawURL,
                                defaultSelected: defaultSelected,
                                note: note)
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
        openSettingsAlert(
            title: "Camera access needed",
            message: "Enable camera (and microphone) access for Wispr Video in System Settings › Privacy & Security.",
            anchor: "Privacy_Camera")
    }

    private func showScreenPermissionAlert() {
        openSettingsAlert(
            title: "Screen Recording permission needed",
            message: "To record your screen, enable Wispr Video under System Settings › Privacy & Security › Screen Recording, then try again. You may need to quit and reopen the app after enabling it.",
            anchor: "Privacy_ScreenCapture")
    }

    private func openSettingsAlert(title: String, message: String, anchor: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
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
