import SwiftUI

struct ReceiptReviewView: View {
    @Environment(SplitSessionViewModel.self) private var session
    @State private var showAddItem = false
    @State private var editingItemID: UUID? = nil

    private var receipt: ReceiptData { session.receipt ?? .empty }

    var body: some View {
        ZStack {
            Color.splitBg.ignoresSafeArea()
            backgroundGradient

            ScrollView {
                VStack(spacing: 16) {
                    // Totals summary card
                    summaryCard

                    // Discrepancy warning
                    if let discrepancy = receipt.totalDiscrepancy {
                        discrepancyBanner(discrepancy: discrepancy)
                    }

                    // Food items section
                    if !receipt.items.isEmpty {
                        itemSection(title: "Food & Drinks", items: receipt.items, color: Color.splitAccent)
                    }

                    // Surcharges section
                    if !receipt.surcharges.isEmpty {
                        itemSection(title: "Tax & Fees", items: receipt.surcharges, color: Color.splitWarn)
                    }

                    // Discounts section
                    if !receipt.discounts.isEmpty {
                        itemSection(title: "Discounts", items: receipt.discounts, color: Color(red: 0.55, green: 0.90, blue: 0.46))
                    }

                    // Empty state
                    if receipt.items.isEmpty && receipt.surcharges.isEmpty && receipt.discounts.isEmpty {
                        emptyState
                    }

                    // Add item button
                    addItemButton

                    // Continue button
                    continueButton

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Review Receipt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Continue") {
                    session.navigate(to: .splitSetup)
                }
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.splitTeal)
                .disabled(receipt.items.isEmpty && receipt.surcharges.isEmpty)
            }
        }
        .sheet(isPresented: $showAddItem) {
            AddLineItemSheet(baseAmount: receipt.foodSubtotal) { item in
                session.addLineItem(item)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color.splitTeal.opacity(0.06), Color.clear],
            startPoint: .top,
            endPoint: .center
        )
        .ignoresSafeArea()
    }

    private var summaryCard: some View {
        GlassCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Subtotal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    CurrencyText(amount: receipt.foodSubtotal,
                                 font: .system(.title3, design: .rounded, weight: .bold))
                }
                Spacer()

                if receipt.surchargeTotal > 0 {
                    VStack(alignment: .center, spacing: 4) {
                        Text("Tax & Fees")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        CurrencyText(amount: receipt.surchargeTotal,
                                     font: .system(.title3, design: .rounded, weight: .bold),
                                     color: Color.splitWarn)
                    }
                    Spacer()
                }

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    CurrencyText(amount: receipt.grandTotal,
                                 font: .system(.title2, design: .rounded, weight: .bold),
                                 color: Color.splitTeal)
                }
            }
        }
    }

    private func discrepancyBanner(discrepancy: Decimal) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.splitWarn)
            VStack(alignment: .leading, spacing: 2) {
                Text("Total mismatch")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                Text("AI scanned \(receipt.parsedTotal?.currencyString ?? "–"), computed \(receipt.grandTotal.currencyString). Please review items.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.splitWarn.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.splitWarn.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func itemSection(title: String, items: [LineItem], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(color)
                Spacer()
                let total = items.reduce(Decimal(0)) { $0 + $1.amount }
                CurrencyText(amount: total, font: .caption, color: .secondary)
            }

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        LineItemRow(
                            item: item,
                            baseAmount: receipt.foodSubtotal,
                            editingItemID: $editingItemID,
                            onUpdate: { session.updateLineItem($0) },
                            onDelete: { session.deleteLineItem(item) }
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        if idx < items.count - 1 {
                            Divider()
                                .overlay(Color.white.opacity(0.07))
                                .padding(.leading, 56)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        GlassCard {
            VStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("No items found")
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(.primary)
                Text("Add items manually using the button below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var addItemButton: some View {
        Button {
            showAddItem = true
        } label: {
            Label("Add Item", systemImage: "plus.circle.fill")
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(Color.splitTeal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.splitTeal.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.splitTeal.opacity(0.3), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private var continueButton: some View {
        Button {
            session.navigate(to: .splitSetup)
        } label: {
            HStack {
                Text("Continue")
                Image(systemName: "arrow.right")
            }
            .font(.system(.body, design: .rounded, weight: .semibold))
            .foregroundStyle(Color.splitBg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.splitTeal, Color.splitAccent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(receipt.items.isEmpty && receipt.surcharges.isEmpty)
        .padding(.top, 8)
    }
}
