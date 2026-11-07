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
    var tripID: UUID? = nil
    var tripName: String? = nil
    var initialCurrency = "USD"
    var onBack: (() -> Void)? = nil
    var onReceipt: ((ReceiptData?, String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var session = SplitSessionViewModel()
    @State private var showScanner = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isProcessingPhoto = false
    @State private var processingError: String?
    @State private var appeared = false
    @State private var currencyInitialized = false

    var body: some View {
        NavigationStack(path: $session.navigationPath) {
            ZStack {
                Color.splitBg.ignoresSafeArea()

                // Ambient glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.splitAccent.opacity(0.12), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 220
                        )
                    )
                    .frame(width: 440, height: 440)
                    .offset(y: -60)
                    .blur(radius: 60)
                    .allowsHitTesting(false)
                    .frame(width: 0, height: 0)

                VStack(spacing: 0) {
                    Spacer()
                    heroSection
                    Spacer()
                    Picker("Paying currency", selection: Binding(get: { session.currencyCode }, set: { session.currencyCode = $0 })) {
                        ForEach(TripCurrency.codes, id: \.self) { Text($0).tag($0) }
                    }.tint(.splitAccent).padding(.bottom, 16).accessibilityIdentifier("bill.currency")
                    actionCards
                        .padding(.bottom, 60)
                }
                .padding(.horizontal, 24)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if let onBack { onBack() } else { dismiss() }
                    } label: {
                        if onBack == nil && tripName == nil { Text("Home") } else { Image(systemName: "chevron.left") }
                    }
                    .accessibilityLabel(tripName == nil ? "Home" : "Cancel")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(for: SplitTabRoute.self) { route in
                destination(for: route)
            }
            .sheet(isPresented: $showScanner) {
                ScannerView(tripID: tripID) { receipt in
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
        .tripError(Binding(get: { session.calculationError }, set: { session.calculationError = $0 }))
        .tripError(Binding(get: { session.historyError }, set: { session.historyError = $0 }))
        .environment(session)
        .environment(\.tripCurrencyCode, session.currencyCode)
        .preferredColorScheme(.dark)
        .onAppear {
            session.activityTripID = tripID
            if !currencyInitialized { session.currencyCode = initialCurrency; currencyInitialized = true }
            withAnimation(.spring(response: 0.8, dampingFraction: 0.75).delay(0.1)) {
                appeared = true
            }
        }
    }

    // MARK: - Subviews

    private var heroSection: some View {
        VStack(spacing: 24) {
            ZStack {
                // Outer glow ring
                Circle()
                    .fill(Color.splitAccent.opacity(0.08))
                    .frame(width: 110, height: 110)

                Circle()
                    .fill(Color.splitAccent)
                    .frame(width: 80, height: 80)
                    .shadow(color: Color.splitAccent.opacity(0.3), radius: 20, y: 4)

                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.black.opacity(0.8))
            }
            .scaleEffect(appeared ? 1 : 0.5)
            .opacity(appeared ? 1 : 0)

            VStack(spacing: 8) {
                Text(tripName == nil ? "SplitTab" : "Add Expense")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(tripName.map { "Add a shared expense to \($0)" } ?? "Split your bills instantly")
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
        }
    }

    private var actionCards: some View {
        VStack(spacing: 12) {
            // Scan receipt — primary
            Button {
                showScanner = true
            } label: {
                primaryActionCard
            }
            .accessibilityIdentifier("capture.scan")
            .accessibilityLabel("Scan Receipt")
            .buttonStyle(.plain)
            .disabled(isProcessingPhoto)
            .scaleEffect(appeared ? 1 : 0.95)
            .opacity(appeared ? 1 : 0)

            HStack(spacing: 12) {
                // Choose photo
                PhotosPicker(selection: $photoItem, matching: .images) {
                    secondaryCard(
                        icon: "photo.on.rectangle.angled",
                        title: isProcessingPhoto ? "Processing..." : "Choose Photo",
                        showSpinner: isProcessingPhoto
                    )
                }
                .disabled(isProcessingPhoto)
                .buttonStyle(.plain)

                // Manual entry
                Button {
                    if let onReceipt { onReceipt(nil, session.currencyCode) }
                    else { session.setReceipt(.empty); session.navigate(to: .receiptReview) }
                } label: {
                    secondaryCard(
                        icon: "square.and.pencil",
                        title: "Manual Entry",
                        accent: .splitCoral
                    )
                }
                .buttonStyle(.plain)
                .disabled(isProcessingPhoto)
            }
            .scaleEffect(appeared ? 1 : 0.95)
            .opacity(appeared ? 1 : 0)
        }
    }

    private var primaryActionCard: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.splitAccent)
                    .frame(width: 48, height: 48)
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.8))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Scan Receipt")
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Text("Take a photo of your receipt")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer()

            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.splitAccent)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.splitAccent.opacity(0.15)))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.splitAccent.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func secondaryCard(icon: String, title: String, showSpinner: Bool = false, accent: Color = .splitViolet) -> some View {
        VStack(spacing: 12) {
            if showSpinner {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.8)
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 28, height: 28)
            }

            Text(title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(accent.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(accent.opacity(0.18), lineWidth: 1)
                )
        )
    }

    // MARK: - Navigation Destinations

    @ViewBuilder
    private func destination(for route: SplitTabRoute) -> some View {
        switch route {
        case .scanner:
            ScannerView(tripID: tripID) { receipt in
                session.setReceipt(receipt)
                session.navigate(to: .receiptReview)
            }
        case .receiptReview:
            ReceiptReviewView(onContinue: onReceipt.map { callback in { callback(session.receipt, session.currencyCode) } })
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
                let receipt = try await ReceiptScannerService.scanAndParse(image: image, originalData: data, tripID: tripID)
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
