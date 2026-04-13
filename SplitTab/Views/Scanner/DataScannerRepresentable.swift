import SwiftUI
import AVFoundation

struct DataScannerRepresentable: UIViewControllerRepresentable {
    @Binding var isScanning: Bool
    /// Set to true to trigger a photo capture; automatically reset after capture fires.
    @Binding var captureTrigger: Bool
    var onImageCaptured: (UIImage) -> Void
    var onCaptureError: ((Error) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageCaptured: onImageCaptured, onCaptureError: onCaptureError)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .black
        let coordinator = context.coordinator

        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else { return }
            DispatchQueue.main.async {
                coordinator.setupSession(in: vc.view)
                if self.isScanning {
                    coordinator.startSession()
                }
            }
        }

        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.onImageCaptured = onImageCaptured
        coordinator.onCaptureError = onCaptureError

        if isScanning {
            coordinator.startSession()
        } else {
            coordinator.stopSession()
        }

        if captureTrigger {
            let resetBinding = _captureTrigger
            coordinator.capturePhoto {
                resetBinding.wrappedValue = false
            }
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, AVCapturePhotoCaptureDelegate {
        private let session = AVCaptureSession()
        private let photoOutput = AVCapturePhotoOutput()
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private var isSessionConfigured = false
        private var isCaptureInFlight = false

        var onImageCaptured: (UIImage) -> Void
        var onCaptureError: ((Error) -> Void)?

        private var captureCompletion: (() -> Void)?

        init(onImageCaptured: @escaping (UIImage) -> Void,
             onCaptureError: ((Error) -> Void)?) {
            self.onImageCaptured = onImageCaptured
            self.onCaptureError = onCaptureError
        }

        // MARK: Session Setup

        func setupSession(in view: UIView) {
            guard !isSessionConfigured else { return }

            session.beginConfiguration()
            session.sessionPreset = .photo

            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: camera),
                  session.canAddInput(input) else {
                session.commitConfiguration()
                return
            }
            session.addInput(input)

            guard session.canAddOutput(photoOutput) else {
                session.commitConfiguration()
                return
            }
            session.addOutput(photoOutput)
            session.commitConfiguration()

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = view.bounds
            view.layer.insertSublayer(preview, at: 0)
            previewLayer = preview

            // Keep preview sized to the view
            NotificationCenter.default.addObserver(
                forName: UIDevice.orientationDidChangeNotification,
                object: nil, queue: .main
            ) { [weak self, weak view] _ in
                guard let view else { return }
                self?.previewLayer?.frame = view.bounds
            }

            isSessionConfigured = true
        }

        func startSession() {
            guard isSessionConfigured, !session.isRunning else { return }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }
        }

        func stopSession() {
            guard session.isRunning else { return }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.stopRunning()
            }
        }

        // MARK: Capture

        func capturePhoto(onReset: @escaping @MainActor () -> Void) {
            guard !isCaptureInFlight else {
                Task { @MainActor in onReset() }
                return
            }
            isCaptureInFlight = true
            captureCompletion = { Task { @MainActor in onReset() } }

            let settings = AVCapturePhotoSettings()
            photoOutput.capturePhoto(with: settings, delegate: self)
        }

        // MARK: AVCapturePhotoCaptureDelegate

        func photoOutput(_ output: AVCapturePhotoOutput,
                         didFinishProcessingPhoto photo: AVCapturePhoto,
                         error: Error?) {
            defer {
                isCaptureInFlight = false
                captureCompletion?()
                captureCompletion = nil
            }

            if let error {
                DispatchQueue.main.async { [weak self] in
                    self?.onCaptureError?(error)
                }
                return
            }

            guard let data = photo.fileDataRepresentation(),
                  let image = UIImage(data: data) else {
                DispatchQueue.main.async { [weak self] in
                    let err = NSError(domain: "SplitTab", code: -1,
                                      userInfo: [NSLocalizedDescriptionKey: "Could not create image from capture data."])
                    self?.onCaptureError?(err)
                }
                return
            }

            DispatchQueue.main.async { [weak self] in
                self?.onImageCaptured(image)
            }
        }

        // MARK: Layout

        func updatePreviewFrame(_ bounds: CGRect) {
            previewLayer?.frame = bounds
        }
    }
}
