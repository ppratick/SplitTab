import SwiftUI
import PhotosUI

enum SplitTabRoute: Hashable {
    case scanner
    case receiptReview
    case splitSetup
    case itemAssignment
    case results
}

struct HomeView: View {
    @State private var session = SplitSessionViewModel()
    @State private var showScanner = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isProcessingPhoto = false
    @State private var processingError: String?
    @State private var appeared = false

    var body: some View {
        NavigationStack(path: $session.navigationPath) {
            ZStack {
                Color.splitBg.ignoresSafeArea()
                backgroundGradient

                VStack(spacing: 0) {
                    Spacer()
                    heroSection
                    Spacer()
                    actionCards
                    Spacer(minLength: 48)
                }
                .padding(.horizontal, 20)
            }
            .navigationBarHidden(true)
            .navigationDestination(for: SplitTabRoute.self) { route in
                destination(for: route)
            }
            .sheet(isPresented: $showScanner) {
                ScannerView { receipt in
                    session.setReceipt(receipt)
                    session.navigate(to: .receiptReview)
                }
                .ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, newItem in
                guard let newItem else { return }
                processPhoto(newItem)
            }
            .alert("Error", isPresented: .constant(processingError != nil)) {
                Button("OK") { processingError = nil }
            } message: {
                Text(processingError ?? "")
            }
        }
        .environment(session)
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                appeared = true
            }
        }
    }

    // MARK: - Subviews

    private var backgroundGradient: some View {
        ZStack {
            // Top-left glow
            Circle()
                .fill(Color.splitTeal.opacity(0.08))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: -80, y: -200)

            // Bottom-right glow
            Circle()
                .fill(Color.splitAccent.opacity(0.06))
                .frame(width: 250, height: 250)
                .blur(radius: 70)
                .offset(x: 100, y: 300)
        }
        .ignoresSafeArea()
    }

    private var heroSection: some View {
        VStack(spacing: 20) {
            ZStack {
                // Outer ring
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.splitTeal.opacity(0.4), Color.splitAccent.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 110, height: 110)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.splitTeal, Color.splitAccent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .shadow(color: Color.splitTeal.opacity(0.35), radius: 28, y: 8)

                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.black.opacity(0.8))
            }
            .scaleEffect(appeared ? 1 : 0.5)
            .opacity(appeared ? 1 : 0)

            VStack(spacing: 8) {
                Text("SplitTab")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Split bills the smart way")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
        }
    }

    private var actionCards: some View {
        VStack(spacing: 12) {
            // Scan receipt — primary action
            Button {
                showScanner = true
            } label: {
                actionRow(
                    icon: "camera.viewfinder",
                    title: "Scan Receipt",
                    subtitle: "Take a photo of your receipt",
                    gradient: true
                )
            }
            .buttonStyle(.plain)
            .disabled(isProcessingPhoto)

            // Choose photo
            PhotosPicker(selection: $photoItem, matching: .images) {
                actionRow(
                    icon: "photo.on.rectangle.angled",
                    title: isProcessingPhoto ? "Processing..." : "Choose Photo",
                    subtitle: "Select from your photo library",
                    gradient: false,
                    showSpinner: isProcessingPhoto
                )
            }
            .disabled(isProcessingPhoto)
            .buttonStyle(.plain)

            // Manual entry
            Button {
                session.setReceipt(.empty)
                session.navigate(to: .receiptReview)
            } label: {
                actionRow(
                    icon: "square.and.pencil",
                    title: "Manual Entry",
                    subtitle: "Enter items by hand",
                    gradient: false
                )
            }
            .buttonStyle(.plain)
            .disabled(isProcessingPhoto)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 24)
    }

    private func actionRow(
        icon: String,
        title: String,
        subtitle: String,
        gradient: Bool,
        showSpinner: Bool = false
    ) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        gradient
                        ? AnyShapeStyle(LinearGradient(
                            colors: [Color.splitTeal, Color.splitAccent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing))
                        : AnyShapeStyle(Color.white.opacity(0.08))
                    )
                    .frame(width: 48, height: 48)

                if showSpinner {
                    ProgressView()
                        .tint(gradient ? .black : .white)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(gradient ? .black.opacity(0.8) : .white)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            gradient
                            ? AnyShapeStyle(LinearGradient(
                                colors: [Color.splitTeal.opacity(0.4), Color.splitAccent.opacity(0.2)],
                                startPoint: .leading,
                                endPoint: .trailing))
                            : AnyShapeStyle(Color.white.opacity(0.08)),
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - Navigation Destinations

    @ViewBuilder
    private func destination(for route: SplitTabRoute) -> some View {
        switch route {
        case .scanner:
            ScannerView { receipt in
                session.setReceipt(receipt)
                session.navigate(to: .receiptReview)
            }
        case .receiptReview:
            ReceiptReviewView()
        case .splitSetup:
            SplitSetupView()
        case .itemAssignment:
            ItemAssignmentView()
        case .results:
            ResultsView()
        }
    }

    // MARK: - Photo Processing

    private func processPhoto(_ item: PhotosPickerItem) {
        isProcessingPhoto = true
        Task {
            defer {
                Task { @MainActor in isProcessingPhoto = false }
            }
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    throw ScanError.invalidImage
                }
                let receipt = try await ReceiptScannerService.scanAndParse(image: image)
                await MainActor.run {
                    session.setReceipt(receipt)
                    session.navigate(to: .receiptReview)
                    photoItem = nil
                }
            } catch {
                await MainActor.run {
                    processingError = error.localizedDescription
                    photoItem = nil
                }
            }
        }
    }
}
