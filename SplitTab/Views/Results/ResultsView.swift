import SwiftUI

struct ResultsView: View {
    @Environment(SplitSessionViewModel.self) private var session
    @State private var appeared = false

    private var result: SplitResult? { session.splitResult }
    private var receipt: ReceiptData? { session.receipt }

    var body: some View {
        ZStack {
            Color.splitBg.ignoresSafeArea()
            backgroundGradient

            if let result {
                ScrollView {
                    VStack(spacing: 20) {
                        // Grand total hero
                        totalHeroCard(result: result)

                        // Meal subtotal / total breakdown
                        if let receipt {
                            mealBreakdownCard(receipt: receipt)
                        }

                        // Fee distribution toggle (only for itemized)
                        if result.splitMode == .itemized {
                            feeToggleSection
                        }

                        // Unassigned items warning
                        if !result.unassignedItems.isEmpty {
                            unassignedWarning(items: result.unassignedItems)
                        }

                        // Per-person cards
                        ForEach(result.personResults) { personResult in
                            PersonResultCard(result: personResult, splitMode: result.splitMode)
                                .transition(.scale(scale: 0.95).combined(with: .opacity))
                        }

                        // Start over
                        startOverButton

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            } else {
                // Fallback — shouldn't normally be reached
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
    }

    // MARK: - Subviews

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color.splitTeal.opacity(0.1), Color.splitAccent.opacity(0.06), Color.clear],
            startPoint: .topLeading,
            endPoint: .center
        )
        .ignoresSafeArea()
    }

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
                                    .foregroundStyle(Color.splitTeal)
                                Text(total.digitsString)
                                    .font(.system(size: 46, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.splitTeal)
                                    .monospacedDigit()
                            }
                        }
                        Text("Total Bill")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // People summary
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("\(result.personResults.count)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("people")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Avatar strip
                HStack(spacing: -8) {
                    ForEach(result.personResults.prefix(6)) { person in
                        Circle()
                            .fill(Person.palette[person.avatarColorIndex % Person.palette.count].gradient)
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
                .fill(Color.splitWarn.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.splitWarn.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func mealBreakdownCard(receipt: ReceiptData) -> some View {
        GlassCard {
            VStack(spacing: 12) {
                breakdownRow("Subtotal", amount: receipt.foodSubtotal, color: .primary)

                if receipt.surchargeTotal > 0 {
                    breakdownRow("Tax & Fees", amount: receipt.surchargeTotal, color: Color.splitWarn)
                }

                if receipt.discountTotal != 0 {
                    breakdownRow("Discounts", amount: receipt.discountTotal,
                                 color: Color(red: 0.55, green: 0.90, blue: 0.46))
                }

                Divider().overlay(Color.white.opacity(0.1))

                HStack {
                    Text("Total")
                        .font(.system(.body, design: .rounded, weight: .bold))
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("$")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.splitTeal)
                        Text(receipt.grandTotal.digitsString)
                            .font(.system(.body, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.splitTeal)
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
                        .fill(Color.white.opacity(0.07))
                )
        }
        .buttonStyle(.plain)
    }
}
