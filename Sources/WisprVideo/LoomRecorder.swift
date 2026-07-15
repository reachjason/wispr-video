import ScreenCaptureKit
import AVFoundation
import CoreImage
import AppKit

/// Records the main display with a circular webcam bubble overlay and microphone
/// audio, compositing everything live into a single .mov via AVAssetWriter.
final class LoomRecorder: NSObject, SCStreamOutput, SCStreamDelegate,
                          AVCaptureVideoDataOutputSampleBufferDelegate,
                          AVCaptureAudioDataOutputSampleBufferDelegate {

    /// Called on the main thread when recording finishes. `nil` == failure.
    var onFinish: ((URL?) -> Void)?

    /// Live camera preview for the floating control panel.
    let previewLayer: AVCaptureVideoPreviewLayer

    // Camera + mic
    private let avSession = AVCaptureSession()
    private let cameraOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var cameraConfigured = false

    // Screen
    private var stream: SCStream?
    private var display: SCDisplay?
    private var streamConfig: SCStreamConfiguration?

    // Compositing
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let sampleQueue = DispatchQueue(label: "com.wisprvideo.loom.samples")
    private let cameraLock = NSLock()
    private var latestCamera: CIImage?

    // Writing
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var sessionStarted = false
    private var outputURL: URL?
    private var outputSize = CGSize.zero
    private var recording = false

    override init() {
        previewLayer = AVCaptureVideoPreviewLayer(session: avSession)
        previewLayer.videoGravity = .resizeAspectFill
        super.init()
    }

    // MARK: - Camera + mic

    @discardableResult
    func configureCameraAndMic() -> Bool {
        if cameraConfigured { return true }
        avSession.beginConfiguration()
        avSession.sessionPreset = .high

        let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
        guard let camera,
              let camInput = try? AVCaptureDeviceInput(device: camera),
              avSession.canAddInput(camInput) else {
            avSession.commitConfiguration()
            return false
        }
        avSession.addInput(camInput)

        cameraOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        cameraOutput.alwaysDiscardsLateVideoFrames = true
        if avSession.canAddOutput(cameraOutput) {
            cameraOutput.setSampleBufferDelegate(self, queue: sampleQueue)
            avSession.addOutput(cameraOutput)
        }

        if let mic = AVCaptureDevice.default(for: .audio),
           let micInput = try? AVCaptureDeviceInput(device: mic),
           avSession.canAddInput(micInput) {
            avSession.addInput(micInput)
            if avSession.canAddOutput(audioOutput) {
                audioOutput.setSampleBufferDelegate(self, queue: sampleQueue)
                avSession.addOutput(audioOutput)
            }
        }

        // Mirror the preview bubble (selfie feel).
        if let conn = previewLayer.connection, conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = true
        }

        avSession.commitConfiguration()
        cameraConfigured = true
        return true
    }

    func startPreview() {
        DispatchQueue.global(qos: .userInitiated).async {
            if !self.avSession.isRunning { self.avSession.startRunning() }
        }
    }

    /// Stops the camera preview when a countdown is cancelled before capture starts.
    func cancelPreview() {
        DispatchQueue.global(qos: .userInitiated).async {
            if self.avSession.isRunning { self.avSession.stopRunning() }
        }
    }

    // MARK: - Screen setup (also verifies Screen Recording permission)

    /// Verifies Screen Recording permission and prepares the capture config + writer.
    /// The content filter is built later, in `beginCapture`, once our control
    /// window exists so it can be excluded from the recording.
    func prepareScreen() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() })
                ?? content.displays.first else {
            throw NSError(domain: "WisprVideo", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "No display available to capture."])
        }

        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true
        config.queueDepth = 6

        self.display = display
        self.streamConfig = config
        self.outputSize = CGSize(width: config.width, height: config.height)

        try setupWriter(size: outputSize)
    }

    private func setupWriter(size: CGSize) throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wispr-loom-\(UUID().uuidString).mov")
        outputURL = url

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: size.width,
                kCVPixelBufferHeightKey as String: size.height,
            ])

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44100,
            AVEncoderBitRateKey: 128000,
        ]
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = true

        if writer.canAdd(videoInput) { writer.add(videoInput) }
        if writer.canAdd(audioInput) { writer.add(audioInput) }
        writer.startWriting()

        self.writer = writer
        self.videoInput = videoInput
        self.audioInput = audioInput
        self.adaptor = adaptor
    }

    // MARK: - Capture control

    /// Starts screen capture, excluding our own control window(s) so they don't
    /// appear in the recording. Pass the control panel's `windowNumber`(s).
    func beginCapture(excludingWindowNumbers windowNumbers: [Int]) async throws {
        guard let display, let streamConfig else {
            throw NSError(domain: "WisprVideo", code: 11,
                          userInfo: [NSLocalizedDescriptionKey: "Screen capture not prepared."])
        }

        // Re-snapshot now that the control window is on screen, and exclude it by ID.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let liveDisplay = content.displays.first { $0.displayID == display.displayID } ?? display
        let ourWindows = content.windows.filter { windowNumbers.contains(Int($0.windowID)) }
        let filter = SCContentFilter(display: liveDisplay, excludingWindows: ourWindows)

        let stream = SCStream(filter: filter, configuration: streamConfig, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        self.stream = stream
        recording = true
        try await stream.startCapture()
    }

    func stop() {
        guard recording else { return }
        recording = false

        Task {
            try? await stream?.stopCapture()
            avSession.stopRunning()

            // Flush any queued sample callbacks, then finalize the inputs on the
            // same queue so no append can race with markAsFinished.
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                sampleQueue.async {
                    self.videoInput?.markAsFinished()
                    self.audioInput?.markAsFinished()
                    cont.resume()
                }
            }

            let ok = await finishWriting()
            let url = outputURL
            await MainActor.run { self.onFinish?(ok ? url : nil) }
        }
    }

    private func finishWriting() async -> Bool {
        guard let writer else { return false }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting { cont.resume() }
        }
        return writer.status == .completed
    }

    // MARK: - SCStreamOutput (screen frames)

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen, recording, sampleBuffer.isValid else { return }

        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRaw), status == .complete,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if !sessionStarted {
            writer?.startSession(atSourceTime: pts)
            sessionStarted = true
        }

        guard let videoInput, videoInput.isReadyForMoreMediaData,
              let adaptor, let pool = adaptor.pixelBufferPool else { return }

        let screenImage = CIImage(cvPixelBuffer: imageBuffer)
        cameraLock.lock(); let cam = latestCamera; cameraLock.unlock()
        let composited = composite(screen: screenImage, camera: cam, canvas: outputSize)

        var outBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outBuffer)
        guard let outBuffer else { return }
        ciContext.render(composited, to: outBuffer)
        adaptor.append(outBuffer, withPresentationTime: pts)
    }

    // MARK: - AVCapture (camera preview frames + mic audio)

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if output === cameraOutput {
            if let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                let image = CIImage(cvPixelBuffer: buffer)
                cameraLock.lock(); latestCamera = image; cameraLock.unlock()
            }
        } else if output === audioOutput {
            guard recording, sessionStarted,
                  let audioInput, audioInput.isReadyForMoreMediaData else { return }
            audioInput.append(sampleBuffer)
        }
    }

    // MARK: - Compositing

    private func composite(screen: CIImage, camera: CIImage?, canvas: CGSize) -> CIImage {
        guard let camera else { return screen }

        let diameter = min(canvas.width, canvas.height) * 0.22

        // Mirror horizontally to match the selfie preview.
        let ext = camera.extent
        var cam = camera
            .transformed(by: CGAffineTransform(scaleX: -1, y: 1))
            .transformed(by: CGAffineTransform(translationX: ext.width, y: 0))

        // Scale to fill a square, then center-crop to the bubble size.
        let camMin = min(cam.extent.width, cam.extent.height)
        let scale = diameter / camMin
        cam = cam.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let square = CGRect(x: cam.extent.midX - diameter / 2,
                            y: cam.extent.midY - diameter / 2,
                            width: diameter, height: diameter)
        cam = cam.cropped(to: square)
            .transformed(by: CGAffineTransform(translationX: -square.minX, y: -square.minY))

        // Circular alpha mask.
        let mask = circleMask(diameter: diameter)
        let clear = CIImage(color: CIColor.clear).cropped(to: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        let masked = cam.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: clear,
            kCIInputMaskImageKey: mask,
        ])

        let margin = diameter * 0.28
        let (px, py) = position(for: Settings.bubbleCorner, canvas: canvas, diameter: diameter, margin: margin)
        let placed = masked.transformed(by: CGAffineTransform(translationX: px, y: py))
        return placed.composited(over: screen)
    }

    private func circleMask(diameter: CGFloat) -> CIImage {
        let r = diameter / 2
        let gradient = CIFilter(name: "CIRadialGradient")!
        gradient.setValue(CIVector(x: r, y: r), forKey: "inputCenter")
        gradient.setValue(r - 1.5, forKey: "inputRadius0")
        gradient.setValue(r, forKey: "inputRadius1")
        gradient.setValue(CIColor(red: 1, green: 1, blue: 1, alpha: 1), forKey: "inputColor0")
        gradient.setValue(CIColor(red: 1, green: 1, blue: 1, alpha: 0), forKey: "inputColor1")
        return gradient.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: diameter, height: diameter))
    }

    private func position(for corner: BubbleCorner, canvas: CGSize,
                          diameter: CGFloat, margin: CGFloat) -> (CGFloat, CGFloat) {
        // Core Image origin is bottom-left.
        let left = margin
        let right = canvas.width - diameter - margin
        let bottom = margin
        let top = canvas.height - diameter - margin
        switch corner {
        case .bottomLeft:  return (left, bottom)
        case .bottomRight: return (right, bottom)
        case .topLeft:     return (left, top)
        case .topRight:    return (right, top)
        }
    }
}
