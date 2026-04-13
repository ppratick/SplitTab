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

                VStack(spacing: 0) {
                    Spacer()
                    heroSection
                    Spacer()
                    actionCards
                    Spacer(minLength: 52)
                }
                .padding(.horizontal, 24)
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
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(0.1)) {
                appeared = true
            }
        }
    }

    // MARK: - Subviews

    private var heroSection: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.splitAccent)
                    .frame(width: 80, height: 80)

                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.black.opacity(0.75))
            }
            .scaleEffect(appeared ? 1 : 0.5)
            .opacity(appeared ? 1 : 0)

            VStack(spacing: 6) {
                Text("SplitTab")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Split your bills instantly")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
        }
    }

    private var actionCards: some View {
        VStack(spacing: 10) {
            // Scan receipt — primary
            Button {
                showScanner = true
            } label: {
                actionRow(
                    icon: "camera.viewfinder",
                    title: "Scan Receipt",
                    subtitle: "Take a photo of your receipt",
                    isPrimary: true
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
                    isPrimary: false,
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
                    subtitle: "Enter items manually",
                    isPrimary: false
                )
            }
            .buttonStyle(.plain)
            .disabled(isProcessingPhoto)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
    }

    private func actionRow(
        icon: String,
        title: String,
        subtitle: String,
        isPrimary: Bool,
        showSpinner: Bool = false
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isPrimary ? Color.splitAccent : Color.white.opacity(0.06))
                    .frame(width: 44, height: 44)

                if showSpinner {
                    ProgressView()
                        .tint(isPrimary ? .black : .white)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isPrimary ? .black.opacity(0.75) : .white)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.2))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            isPrimary ? Color.splitAccent.opacity(0.3) : Color.white.opacity(0.06),
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
