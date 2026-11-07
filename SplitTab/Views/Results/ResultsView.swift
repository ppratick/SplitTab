import SwiftUI

struct ResultsView: View {
    var onSaveToTrip: (() -> Void)? = nil
    @Environment(SplitSessionViewModel.self) private var session
    @State private var appeared = false
    @State private var copiedAll: String?

    private var result: SplitResult? { session.splitResult }
    private var receipt: ReceiptData? { session.receipt }

    var body: some View {
        ZStack {
            Color.splitBg.ignoresSafeArea()

            // Ambient glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.splitAccent.opacity(0.08), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .offset(y: -120)
                .blur(radius: 50)
                .allowsHitTesting(false)
                    .frame(width: 0, height: 0)

            if let result {
                ScrollView {
                    VStack(spacing: 20) {
                        totalHeroCard(result: result)

                        if let receipt {
                            breakdownCard(receipt: receipt)
                        }

                        if result.splitMode == .itemized {
                            if let receipt, !receipt.surcharges.isEmpty {
                                feeToggleSection
                            }
                            if let receipt, !receipt.discounts.isEmpty {
                                discountToggleSection
                            }
                        }

                        if !result.unassignedItems.isEmpty {
                            unassignedWarning(items: result.unassignedItems)
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Send to the group").font(.system(.headline, design: .rounded))
                                Button("Copy everyone’s totals", systemImage: "doc.on.doc") { copyAll(result, breakdown: false) }
                                    .accessibilityIdentifier("copy.all.totals")
                                Button("Copy everyone’s breakdown", systemImage: "list.bullet.clipboard") { copyAll(result, breakdown: true) }
                                    .accessibilityIdentifier("copy.all.breakdown")
                                if let copiedAll { Text(copiedAll).font(.caption).foregroundStyle(Color.splitAccent) }
                            }.frame(maxWidth: .infinity, alignment: .leading).tint(Color.splitAccent)
                        }

                        VStack(spacing: 12) {
                            ForEach(result.personResults) { personResult in
                                PersonResultCard(result: personResult, splitMode: result.splitMode)
                                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                            }
                        }

                        if let onSaveToTrip {
                            Button("Save to trip", action: onSaveToTrip)
                                .buttonStyle(.borderedProminent).tint(Color.splitAccent)
                        } else { startOverButton }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Calculating…")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .preferredColorScheme(.dark)
        .toolbar {
            if let onSaveToTrip {
                ToolbarItem(placement: .confirmationAction) { Button("Save to trip", action: onSaveToTrip) }
            }
        }
        .onAppear {
            session.calculate()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { appeared = true }
        }
        .onChange(of: session.feeDistribution) { _, _ in
            session.calculate()
        }
        .onChange(of: session.discountDistribution) { _, _ in
            session.calculate()
        }
    }

    private func copyAll(_ result: SplitResult, breakdown: Bool) {
        do {
            try ShareClipboard.copy(SplitCopyText.everyone(result, currency: session.currencyCode, title: receipt?.merchantName, breakdown: breakdown))
            copiedAll = breakdown ? "Everyone’s breakdown copied" : "Everyone’s totals copied"
        } catch { session.calculationError = error.localizedDescription }
    }

    // MARK: - Subviews

    private func totalHeroCard(result: SplitResult) -> some View {
        GlassHeroCard {
            VStack(spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(result.splitMode == .even ? "Even Split" : "Itemized Split")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(.white.opacity(0.4))
                            .textCase(.uppercase)
                            .tracking(0.5)

                        if let total = receipt?.grandTotal {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(session.currencyCode)
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.splitAccent)
                                Text(total.currencyDigits(session.currencyCode))
                                    .minimumScaleFactor(0.5).lineLimit(1)
                                    .font(.system(size: 42, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .monospacedDigit()
                            }
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        Text("\(result.personResults.count)")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("people")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }

                // Avatar row with accent bar
                VStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.splitAccent.opacity(0.2))
                        .frame(height: 2)

                    HStack(spacing: -8) {
                        ForEach(result.personResults.prefix(6)) { person in
                            Circle()
                                .fill(Person.palette[person.avatarColorIndex % Person.palette.count])
                                .frame(width: 30, height: 30)
                                .overlay(Circle().strokeBorder(Color.splitBg, lineWidth: 2))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
    }

    private var feeToggleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tax & Fee Distribution")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.leading, 4)

            FeeToggleBar(selection: Binding<FeeDistribution>(
                get: { session.feeDistribution },
                set: { session.feeDistribution = $0 }
            ))
        }
    }

    private var discountToggleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Discount Distribution")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.leading, 4)

            FeeToggleBar(selection: Binding<FeeDistribution>(
                get: { session.discountDistribution },
                set: { session.discountDistribution = $0 }
            ), accent: .splitViolet)
        }
    }

    private func unassignedWarning(items: [LineItem]) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.splitWarn)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(items.count) item\(items.count == 1 ? "" : "s") split evenly")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                Text(items.map(\.name).joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.splitWarn.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.splitWarn.opacity(0.15), lineWidth: 1)
                )
        )
    }

    private func breakdownCard(receipt: ReceiptData) -> some View {
        GlassCard {
            VStack(spacing: 14) {
                breakdownRow("Subtotal", amount: receipt.itemSubtotal, color: .primary)

                if receipt.surchargeTotal > 0 {
                    breakdownRow("Tax & Fees", amount: receipt.surchargeTotal, color: Color.splitWarn)
                }

                if receipt.discountTotal != 0 {
                    breakdownRow("Discounts", amount: receipt.discountTotal, color: Color.splitViolet)
                }

                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)

                HStack {
                    Text("Total")
                        .font(.system(.body, design: .rounded, weight: .bold))
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(session.currencyCode)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.splitAccent)
                        Text(receipt.grandTotal.currencyDigits(session.currencyCode))
                            .font(.system(.body, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.splitAccent)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private func breakdownRow(_ label: String, amount: Decimal, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
            CurrencyText(amount: amount,
                         font: .system(.subheadline, design: .rounded, weight: .semibold),
                         color: color)
        }
    }

    private var startOverButton: some View {
        Button {
            session.startOver()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .bold))
                Text("Start Over")
            }
            .font(.system(.body, design: .rounded, weight: .semibold))
            .foregroundStyle(.white.opacity(0.4))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
