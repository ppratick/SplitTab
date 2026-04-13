import SwiftUI
import AVFoundation

struct ScannerView: View {
    var onScanned: (ReceiptData) -> Void

    @State private var isScanning = true
    @State private var captureTrigger = false
    @State private var isProcessing = false
    @State private var frozenFrame: UIImage? = nil
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil {
                DataScannerRepresentable(
                    isScanning: $isScanning,
                    captureTrigger: $captureTrigger,
                    onImageCaptured: { image in
                        frozenFrame = image
                        Task { await process(image: image) }
                    },
                    onCaptureError: { err in
                        frozenFrame = nil
                        error = err.localizedDescription
                        isProcessing = false
                    }
                )
                .ignoresSafeArea()
            } else {
                unavailableView
            }

            if frozenFrame != nil {
                Color.clear
                    .ignoresSafeArea()
                    .overlay {
                        Image(uiImage: frozenFrame!)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
                    .ignoresSafeArea()
            }

            receiptGuideOverlay

            VStack {
                topBar
                Spacer()
                bottomBar
            }
            .ignoresSafeArea(edges: .top)
        }
        .interactiveDismissDisabled(isProcessing)
        .alert("Scan Error", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    // MARK: - Subviews

    private var topBar: some View {
        HStack {
            Button {
                guard !isProcessing else { return }
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.regularMaterial))
                    .opacity(isProcessing ? 0.35 : 1.0)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Scan Receipt")
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial.opacity(0.8))
    }

    private var bottomBar: some View {
        VStack(spacing: 16) {
            Text("Analyzing with AI...")
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
                .opacity(isProcessing ? 1 : 0)

            Button {
                guard !isProcessing else { return }
                isProcessing = true
                captureTrigger = true
            } label: {
                Label("Use This Scan", systemImage: "checkmark.circle.fill")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Capsule().fill(Color.splitAccent))
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
            .padding(.horizontal, 24)
        }
        .padding(.vertical, 28)
        .background(.ultraThinMaterial)
    }

    private var receiptGuideOverlay: some View {
        GeometryReader { geo in
            let w = geo.size.width * 0.82
            let h = geo.size.height * 0.55
            let x = (geo.size.width - w) / 2
            let y = (geo.size.height - h) / 2
            let arm: CGFloat = 28
            let r: CGFloat = 6

            ZStack {
                Color.black.opacity(0.45)
                    .mask(
                        Rectangle()
                            .overlay(
                                RoundedRectangle(cornerRadius: r)
                                    .frame(width: w, height: h)
                                    .blendMode(.destinationOut)
                            )
                            .compositingGroup()
                    )

                Path { path in
                    path.move(to: CGPoint(x: x, y: y + arm))
                    path.addLine(to: CGPoint(x: x, y: y + r))
                    path.addQuadCurve(to: CGPoint(x: x + r, y: y), control: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x + arm, y: y))
                    path.move(to: CGPoint(x: x + w - arm, y: y))
                    path.addLine(to: CGPoint(x: x + w - r, y: y))
                    path.addQuadCurve(to: CGPoint(x: x + w, y: y + r), control: CGPoint(x: x + w, y: y))
                    path.addLine(to: CGPoint(x: x + w, y: y + arm))
                    path.move(to: CGPoint(x: x + w, y: y + h - arm))
                    path.addLine(to: CGPoint(x: x + w, y: y + h - r))
                    path.addQuadCurve(to: CGPoint(x: x + w - r, y: y + h), control: CGPoint(x: x + w, y: y + h))
                    path.addLine(to: CGPoint(x: x + w - arm, y: y + h))
                    path.move(to: CGPoint(x: x + arm, y: y + h))
                    path.addLine(to: CGPoint(x: x + r, y: y + h))
                    path.addQuadCurve(to: CGPoint(x: x, y: y + h - r), control: CGPoint(x: x, y: y + h))
                    path.addLine(to: CGPoint(x: x, y: y + h - arm))
                }
                .stroke(Color.splitAccent.opacity(0.7), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
    }

    private var unavailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Live scanning is not available.\nPlease use \"Choose Photo\" instead.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - Processing

    @MainActor
    private func process(image: UIImage) async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            let receipt = try await OpenAIReceiptService.parseReceipt(image: image)
            onScanned(receipt)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
