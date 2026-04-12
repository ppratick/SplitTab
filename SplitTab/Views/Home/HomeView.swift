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
                // Background
                Color.splitBg.ignoresSafeArea()
                backgroundGradient

                VStack(spacing: 0) {
                    Spacer()
                    heroSection
                    Spacer()
                    ctaSection
                    Spacer(minLength: 48)
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
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) {
                appeared = true
            }
        }
    }

    // MARK: - Subviews

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color.splitTeal.opacity(0.12),
                Color.splitAccent.opacity(0.06),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var heroSection: some View {
        VStack(spacing: 24) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.splitTeal, Color.splitAccent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                    .shadow(color: Color.splitTeal.opacity(0.4), radius: 24, y: 8)

                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(.black.opacity(0.8))
            }
            .scaleEffect(appeared ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)

            VStack(spacing: 8) {
                Text("SplitTab")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Scan a receipt, split the bill")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
        }
    }

    private var ctaSection: some View {
        VStack(spacing: 14) {
            // Primary CTA — scan
            Button {
                showScanner = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Scan Receipt")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                }
                .foregroundStyle(isProcessingPhoto ? Color.secondary : Color.splitBg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    Capsule()
                        .fill(
                            isProcessingPhoto
                            ? AnyShapeStyle(Color.white.opacity(0.1))
                            : AnyShapeStyle(LinearGradient(
                                colors: [Color.splitTeal, Color.splitAccent],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                        )
                        .shadow(color: isProcessingPhoto ? .clear : Color.splitTeal.opacity(0.35), radius: 16, y: 6)
                )
            }
            .buttonStyle(.plain)
            .disabled(isProcessingPhoto)

            // Secondary CTA — photo picker
            PhotosPicker(selection: $photoItem, matching: .images) {
                HStack(spacing: 12) {
                    if isProcessingPhoto {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    Text(isProcessingPhoto ? "Processing..." : "Choose Photo")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    Capsule()
                        .fill(.regularMaterial)
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                        )
                )
            }
            .disabled(isProcessingPhoto)
            .buttonStyle(.plain)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 24)
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
