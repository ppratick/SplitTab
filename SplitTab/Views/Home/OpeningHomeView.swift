import SwiftUI

struct OpeningHomeView: View {
    let store: TripStore?
    let failure: String?
    let retry: () -> Void
    @State private var destination: Destination?
    @State private var showingSettings = false
    @AppStorage("recentTripID") private var recentTripID = ""
    enum Destination: String, Identifiable { case bill, trips, recent; var id: String { rawValue } }
    private var recent: TripRecord? {
        guard let store else { return nil }
        return store.trips.first { $0.id.uuidString == recentTripID }
            ?? store.trips.sorted {
                if ($0.status == .active) != ($1.status == .active) { return $0.status == .active }
                return $0.latestActivity > $1.latestActivity
            }.first
    }
    var body: some View {
        NavigationStack {
        ZStack {
            Color.splitBg.ignoresSafeArea()
            Circle().fill(Color.splitAccent.opacity(0.1)).frame(width: 300, height: 300).blur(radius: 85).offset(y: -220).allowsHitTesting(false)
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("SplitTab").font(.system(size: 42, weight: .bold, design: .rounded))
                            Spacer()
                            Button { showingSettings = true } label: {
                                Image(systemName: "gearshape").font(.title2).foregroundStyle(Color.splitAccent)
                                    .frame(width: 44, height: 44)
                            }.accessibilityLabel("Settings").accessibilityIdentifier("home.settings")
                        }
                        Text("Good times. Fair shares.").font(.system(.title3, design: .rounded)).foregroundStyle(.secondary)
                    }.padding(.top, 16).padding(.bottom, 10)
                    VStack(spacing: 16) {
                        choice("Split a bill", subtitle: "One receipt, everyone’s share.", icon: "receipt", prominent: true) { destination = .bill }
                        choice("Trips", subtitle: "Track shared expenses and settle later.", icon: "suitcase.rolling", prominent: false) { destination = .trips }
                    }
                    if let trip = recent {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("PICK UP WHERE YOU LEFT OFF").font(.system(.caption2, design: .rounded, weight: .bold)).tracking(1.2).foregroundStyle(.secondary)
                            Button { destination = .recent } label: {
                                GlassCard {
                                    HStack(spacing: 14) {
                                        Image(systemName: "suitcase").foregroundStyle(Color.splitViolet)
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(trip.name).font(.system(.headline, design: .rounded))
                                            Text(tripPosition(trip.balances[trip.me] ?? 0, trip: trip, me: true)).font(.system(.caption, design: .rounded)).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.up.right").font(.caption.bold()).foregroundStyle(.secondary)
                                    }
                                }
                            }.buttonStyle(.plain).accessibilityIdentifier("home.recent")
                        }.padding(.top, 8)
                    }
                    if let store {
                        NavigationLink { ArchiveLibraryView(store: store) } label: {
                            Label("Receipts & history", systemImage: "clock.arrow.circlepath")
                        }.accessibilityIdentifier("home.archive")
                    }
                    Spacer(minLength: 24)
                }.padding(.horizontal, 24)
            }
        }
        }
        .sheet(isPresented: $showingSettings) { ReceiptSettingsView() }
        .fullScreenCover(item: $destination) { destination in
            switch destination {
            case .bill: HomeView()
            case .trips:
                if let store { TripListView().environment(store) }
                else { unavailable }
            case .recent:
                if let store, let recent {
                    NavigationStack { TripDetailView(tripID: recent.id).toolbar { ToolbarItem(placement: .topBarLeading) { Button("Home") { self.destination = nil } } } }.environment(store)
                } else { unavailable }
            }
        }
    }
    private var unavailable: some View {
        NavigationStack {
            ContentUnavailableView { Label("Trip storage unavailable", systemImage: "externaldrive.badge.exclamationmark") }
            description: { Text(failure ?? "Opening saved trips…") }
            actions: { Button("Retry", action: retry) }
            .toolbar { Button("Home") { destination = nil } }
        }
    }
    private func choice(_ title: String, subtitle: String, icon: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        let accent: Color = prominent ? .splitAccent : .splitViolet
        return Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.system(size: 25, weight: .medium))
                    .foregroundStyle(prominent ? Color.black.opacity(0.8) : accent)
                    .frame(width: 54, height: 58)
                    .background(RoundedRectangle(cornerRadius: 16).fill(prominent ? accent : accent.opacity(0.1)))
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(.white)
                    Text(subtitle).font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right").font(.caption.bold()).foregroundStyle(accent)
            }.padding(20)
            .background(RoundedRectangle(cornerRadius: 24).fill(Color.white.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(accent.opacity(prominent ? 0.25 : 0.08)))
        }.buttonStyle(.plain).accessibilityIdentifier(title == "Trips" ? "home.trips" : "home.bill")
    }
}
