import AVFoundation
import Capacitor
import Photos

@objc(RecordingPlugin)
public final class RecordingPlugin: CAPPlugin, CAPBridgedPlugin, AVCaptureFileOutputRecordingDelegate {
    public let identifier = "RecordingPlugin"
    public let jsName = "NativeRecording"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "start", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stop", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "status", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "test", returnType: CAPPluginReturnPromise),
    ]

    private let captureSession = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "com.n0thytvoff.prepatrack.recording")
    private var configured = false
    private var startedAt: Date?
    private var currentURL: URL?
    private var stopCalls: [CAPPluginCall] = []

    @objc func start(_ call: CAPPluginCall) {
        requestPermissions { [weak self] granted in
            guard let self else { return }
            guard granted else {
                call.reject("Autorise la caméra, le microphone et l’ajout à Photos dans Réglages iOS.")
                return
            }
            self.sessionQueue.async {
                do {
                    try self.configureIfNeeded()
                    guard !self.movieOutput.isRecording else {
                        DispatchQueue.main.async {
                            call.resolve(["startedAt": (self.startedAt ?? Date()).timeIntervalSince1970 * 1_000])
                        }
                        return
                    }
                    if !self.captureSession.isRunning { self.captureSession.startRunning() }
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("prepatrack-\(UUID().uuidString).mov")
                    self.currentURL = url
                    self.startedAt = Date()
                    self.movieOutput.maxRecordedDuration = CMTime(seconds: 3_600, preferredTimescale: 600)
                    self.movieOutput.movieFragmentInterval = CMTime(seconds: 10, preferredTimescale: 600)
                    self.movieOutput.startRecording(to: url, recordingDelegate: self)
                    DispatchQueue.main.async {
                        UIApplication.shared.isIdleTimerDisabled = true
                        call.resolve(["startedAt": self.startedAt!.timeIntervalSince1970 * 1_000])
                    }
                } catch {
                    DispatchQueue.main.async { call.reject(error.localizedDescription) }
                }
            }
        }
    }

    @objc func stop(_ call: CAPPluginCall) {
        sessionQueue.async {
            guard self.movieOutput.isRecording else {
                DispatchQueue.main.async { call.resolve(["saved": false]) }
                return
            }
            self.stopCalls.append(call)
            self.movieOutput.stopRecording()
        }
    }

    @objc func status(_ call: CAPPluginCall) {
        var result: [String: Any] = ["recording": movieOutput.isRecording]
        if let startedAt { result["startedAt"] = startedAt.timeIntervalSince1970 * 1_000 }
        call.resolve(result)
    }

    @objc func test(_ call: CAPPluginCall) {
        requestPermissions { granted in
            granted ? call.resolve() : call.reject("Permissions caméra, microphone ou Photos refusées.")
        }
    }

    public func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        let successfullyFinished = (error as NSError?)?
            .userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? (error == nil)
        guard successfullyFinished else {
            finish(saved: false, error: error?.localizedDescription ?? "Enregistrement interrompu")
            return
        }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
        }) { [weak self] saved, error in
            self?.finish(saved: saved, error: error?.localizedDescription)
        }
    }

    private func finish(saved: Bool, error: String?) {
        sessionQueue.async {
            self.captureSession.stopRunning()
            if let url = self.currentURL { try? FileManager.default.removeItem(at: url) }
            self.currentURL = nil
            self.startedAt = nil
            let calls = self.stopCalls
            self.stopCalls.removeAll()
            DispatchQueue.main.async {
                UIApplication.shared.isIdleTimerDisabled = false
                let payload: [String: Any] = ["saved": saved, "error": error as Any]
                calls.forEach { saved ? $0.resolve(payload) : $0.reject(error ?? "La vidéo n’a pas pu être ajoutée à Photos.") }
                self.notifyListeners("recordingFinished", data: payload)
            }
        }
    }

    private func configureIfNeeded() throws {
        guard !configured else { return }
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        captureSession.sessionPreset = .hd1280x720
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let microphone = AVCaptureDevice.default(for: .audio) else {
            throw RecordingError.deviceUnavailable
        }
        let cameraInput = try AVCaptureDeviceInput(device: camera)
        let microphoneInput = try AVCaptureDeviceInput(device: microphone)
        guard captureSession.canAddInput(cameraInput), captureSession.canAddInput(microphoneInput),
              captureSession.canAddOutput(movieOutput) else {
            throw RecordingError.configurationFailed
        }
        captureSession.addInput(cameraInput)
        captureSession.addInput(microphoneInput)
        captureSession.addOutput(movieOutput)
        if let connection = movieOutput.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        configured = true
    }

    private func requestPermissions(completion: @escaping (Bool) -> Void) {
        let group = DispatchGroup()
        var camera = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        var microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        var photos = PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            group.enter(); AVCaptureDevice.requestAccess(for: .video) { camera = $0; group.leave() }
        }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            group.enter(); AVCaptureDevice.requestAccess(for: .audio) { microphone = $0; group.leave() }
        }
        if PHPhotoLibrary.authorizationStatus(for: .addOnly) == .notDetermined {
            group.enter(); PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                photos = status == .authorized || status == .limited
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(camera && microphone && photos) }
    }
}

private enum RecordingError: LocalizedError {
    case deviceUnavailable
    case configurationFailed
    var errorDescription: String? {
        switch self {
        case .deviceUnavailable: return "Caméra avant ou microphone introuvable."
        case .configurationFailed: return "Impossible de configurer la capture vidéo."
        }
    }
}
