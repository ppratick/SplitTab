import SwiftUI

struct ResultsView: View {
    @Environment(SplitSessionViewModel.self) private var session
    @State private var appeared = false

    private var result: SplitResult? { session.splitResult }
    private var receipt: ReceiptData? { session.receipt }

    var body: some View {
        ZStack {
            Color.splitBg.ignoresSafeArea()

            if let result {
                ScrollView {
                    VStack(spacing: 20) {
                        totalHeroCard(result: result)

                        if let receipt {
                            mealBreakdownCard(receipt: receipt)
                        }

                        if result.splitMode == .itemized {
                            feeToggleSection
                            if let receipt, !receipt.discounts.isEmpty {
                                discountToggleSection
                            }
                        }

                        if !result.unassignedItems.isEmpty {
                            unassignedWarning(items: result.unassignedItems)
                        }

                        ForEach(result.personResults) { personResult in
                            PersonResultCard(result: personResult, splitMode: result.splitMode)
                                .transition(.scale(scale: 0.95).combined(with: .opacity))
                        }

                        startOverButton

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
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { appeared = true }
        }
        .onChange(of: session.feeDistribution) { _, _ in
            session.calculate()
        }
        .onChange(of: session.discountDistribution) { _, _ in
            session.calculate()
        }
    }

    // MARK: - Subviews

    private func totalHeroCard(result: SplitResult) -> some View {
        GlassHeroCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(result.splitMode == .even ? "Even Split" : "Itemized Split")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary)
                        if let total = receipt?.grandTotal {
                            HStack(alignment: .firstTextBaseline, spacing: 1) {
                                Text("$")
                                    .font(.system(size: 26, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.splitAccent)
                                Text(total.digitsString)
                                    .font(.system(size: 46, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.splitAccent)
                                    .monospacedDigit()
                            }
                        }
                        Text("Total Bill")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        Text("\(result.personResults.count)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("people")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: -8) {
                    ForEach(result.personResults.prefix(6)) { person in
                        Circle()
                            .fill(Person.palette[person.avatarColorIndex % Person.palette.count])
                            .frame(width: 28, height: 28)
                            .overlay(Circle().strokeBorder(Color.splitBg, lineWidth: 2))
                    }
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
    }

    private var feeToggleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tax & Fee Distribution")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
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
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            FeeToggleBar(selection: Binding<FeeDistribution>(
                get: { session.discountDistribution },
                set: { session.discountDistribution = $0 }
            ))
        }
    }

    private func unassignedWarning(items: [LineItem]) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.splitWarn)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(items.count) item\(items.count == 1 ? "" : "s") split evenly")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
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
                .fill(Color.splitWarn.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.splitWarn.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func mealBreakdownCard(receipt: ReceiptData) -> some View {
        GlassCard {
            VStack(spacing: 12) {
                breakdownRow("Subtotal", amount: receipt.itemSubtotal, color: .primary)

                if receipt.surchargeTotal > 0 {
                    breakdownRow("Tax & Fees", amount: receipt.surchargeTotal, color: Color.splitWarn)
                }

                if receipt.discountTotal != 0 {
                    breakdownRow("Discounts", amount: receipt.discountTotal, color: Color.splitAccent)
                }

                Divider().overlay(Color.white.opacity(0.08))

                HStack {
                    Text("Total")
                        .font(.system(.body, design: .rounded, weight: .bold))
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("$")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.splitAccent)
                        Text(receipt.grandTotal.digitsString)
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
            Label("Start Over", systemImage: "arrow.counterclockwise")
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
    }
}
