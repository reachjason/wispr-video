import AppKit
import AVFoundation

/// A view that keeps a capture preview layer sized to its bounds.
private final class PreviewHostView: NSView {
    let previewLayer: CALayer
    init(previewLayer: CALayer) {
        self.previewLayer = previewLayer
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(previewLayer)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}

/// Floating always-on-top window shown while recording: live preview + timer + Stop.
final class RecorderPanel: NSPanel {
    var onStop: (() -> Void)?

    private let timerLabel = NSTextField(labelWithString: "00:00")
    private var startDate: Date?
    private var timer: Timer?

    init(previewLayer: CALayer) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 340, height: 500),
                   styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                   backing: .buffered, defer: false)

        isFloatingPanel = true
        level = .floating
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        standardWindowButton(.closeButton)?.isHidden = true
        backgroundColor = NSColor.black

        let container = NSView(frame: contentRect(forFrameRect: frame))
        container.wantsLayer = true

        // Preview fills the window.
        let preview = PreviewHostView(previewLayer: previewLayer)
        preview.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(preview)

        // Bottom control bar.
        let bar = NSVisualEffectView()
        bar.material = .hudWindow
        bar.blendingMode = .withinWindow
        bar.state = .active
        bar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bar)

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = 5
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 10).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 10).isActive = true

        timerLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        timerLabel.textColor = .white

        let stopButton = NSButton(title: "Stop", target: self, action: #selector(stopTapped))
        stopButton.bezelStyle = .rounded
        stopButton.keyEquivalent = "\r"

        let stack = NSStackView(views: [dot, timerLabel, NSView(), stopButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)

        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: container.topAnchor),
            preview.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            preview.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 52),

            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            stack.topAnchor.constraint(equalTo: bar.topAnchor),
            stack.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
        ])

        contentView = container
    }

    func startTimer() {
        startDate = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let start = self.startDate else { return }
            let elapsed = Int(Date().timeIntervalSince(start))
            self.timerLabel.stringValue = String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
        }
    }

    @objc private func stopTapped() {
        onStop?()
    }

    func teardown() {
        timer?.invalidate()
        timer = nil
    }
}
