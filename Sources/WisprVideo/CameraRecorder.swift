import AVFoundation
import AppKit

/// Owns the capture session (camera + mic) and writes a master .mov to a temp file.
final class CameraRecorder: NSObject, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    let previewLayer: AVCaptureVideoPreviewLayer

    /// Called on the main thread when a recording finishes. `nil` URL means failure.
    var onFinish: ((URL?) -> Void)?

    private var configured = false
    private var currentURL: URL?

    override init() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        super.init()
    }

    /// Builds the capture graph once. Returns false if no camera is available.
    @discardableResult
    func configureIfNeeded() -> Bool {
        if configured { return true }
        session.beginConfiguration()
        session.sessionPreset = .high

        let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
        guard let camera,
              let camInput = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(camInput) else {
            session.commitConfiguration()
            return false
        }
        session.addInput(camInput)

        if let mic = AVCaptureDevice.default(for: .audio),
           let micInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(micInput) {
            session.addInput(micInput)
        }

        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }

        session.commitConfiguration()
        configured = true
        return true
    }

    var isRecording: Bool { movieOutput.isRecording }

    /// Starts the session (for preview) then begins recording once it's live.
    func begin() {
        DispatchQueue.global(qos: .userInitiated).async {
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("wispr-\(UUID().uuidString).mov")
                self.currentURL = url
                self.movieOutput.startRecording(to: url, recordingDelegate: self)
            }
        }
    }

    func stop() {
        if movieOutput.isRecording { movieOutput.stopRecording() }
    }

    func teardownSession() {
        DispatchQueue.global(qos: .userInitiated).async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        // A non-nil error can still yield a usable file; treat only fatal cases as failure.
        let ok = error == nil || (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
        DispatchQueue.main.async {
            self.onFinish?(ok ? outputFileURL : nil)
        }
    }
}
