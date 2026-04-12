import SwiftUI
import VisionKit

@available(iOS 16.0, *)
struct DataScannerRepresentable: UIViewControllerRepresentable {
    @Binding var isScanning: Bool
    /// Set to true to trigger a photo capture; automatically reset after capture fires.
    @Binding var captureTrigger: Bool
    var onImageCaptured: (UIImage) -> Void
    var onCaptureError: ((Error) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageCaptured: onImageCaptured, onCaptureError: onCaptureError)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: false
        )
        scanner.delegate = context.coordinator
        context.coordinator.scanner = scanner
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        if isScanning {
            try? uiViewController.startScanning()
        } else {
            uiViewController.stopScanning()
        }

        context.coordinator.onImageCaptured = onImageCaptured
        context.coordinator.onCaptureError = onCaptureError

        if captureTrigger {
            let resetBinding = _captureTrigger
            context.coordinator.capturePhoto {
                resetBinding.wrappedValue = false
            }
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var scanner: DataScannerViewController?
        var onImageCaptured: (UIImage) -> Void
        var onCaptureError: ((Error) -> Void)?
        private var isCaptureInFlight = false

        init(onImageCaptured: @escaping (UIImage) -> Void,
             onCaptureError: ((Error) -> Void)?) {
            self.onImageCaptured = onImageCaptured
            self.onCaptureError = onCaptureError
        }

        func capturePhoto(onReset: @escaping @MainActor () -> Void) {
            guard !isCaptureInFlight, let scanner = scanner else { return }
            isCaptureInFlight = true
            Task { @MainActor [weak self] in
                onReset()
                do {
                    let image = try await scanner.capturePhoto()
                    self?.onImageCaptured(image)
                } catch {
                    self?.onCaptureError?(error)
                }
                self?.isCaptureInFlight = false
            }
        }
    }
}
