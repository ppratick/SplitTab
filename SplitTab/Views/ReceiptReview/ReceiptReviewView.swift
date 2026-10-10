import SwiftUI

struct ReceiptReviewView: View {
    var onContinue: (() -> Void)? = nil
    @Environment(\.tripCurrencyCode) private var tripCurrencyCode
    @Environment(SplitSessionViewModel.self) private var session
    @State private var showAddItem = false
    @State private var invalidItems: Set<UUID> = []

    private var receipt: ReceiptData { session.receipt ?? .empty }

    var body: some View {
        ZStack {
            Color.splitBg.ignoresSafeArea()

            List {
                    if !receipt.items.isEmpty || !receipt.surcharges.isEmpty || !receipt.discounts.isEmpty {
                        Section { summaryCard.listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden) }
                    }

                    if let discrepancy = receipt.totalDiscrepancy {
                        discrepancyBanner(discrepancy: discrepancy)
                    }

                    if !receipt.items.isEmpty {
                        itemSection(title: "Items", count: receipt.items.count, items: receipt.items, color: Color.splitAccent)
                    }

                    if !receipt.surcharges.isEmpty {
                        itemSection(title: "Tax & Fees", count: receipt.surcharges.count, items: receipt.surcharges, color: Color.splitWarn)
                    }

                    if !receipt.discounts.isEmpty {
                        itemSection(title: "Discounts", count: receipt.discounts.count, items: receipt.discounts, color: Color.splitViolet)
                    }

                    if receipt.items.isEmpty && receipt.surcharges.isEmpty && receipt.discounts.isEmpty {
                        Section { emptyState.listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden) }
                    }

                    if !invalidItems.isEmpty {
                        Text("Enter an item name and a valid positive price before continuing.")
                            .font(.caption).foregroundStyle(Color.splitWarn)
                    }
                    Section { addItemButton.padding(.vertical, 4).listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden) }

            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(18)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .keyboardDismissButton()
        .navigationTitle("Review Receipt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Continue") {
                    if let onContinue { onContinue() } else { session.navigate(to: .splitSetup) }
                }
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.splitAccent)
                .disabled((receipt.items.isEmpty && receipt.surcharges.isEmpty) || !invalidItems.isEmpty)
            }
        }
        .sheet(isPresented: $showAddItem) {
            AddLineItemSheet(baseAmount: receipt.itemSubtotal) { item in
                session.addLineItem(item)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private var summaryCard: some View {
        GlassCard(cornerRadius: 24, padding: 22) {
            VStack(spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Subtotal")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                        CurrencyText(amount: receipt.itemSubtotal,
                                     font: .system(.title3, design: .rounded, weight: .bold))
                    }
                    Spacer()

                    if receipt.surchargeTotal > 0 {
                        VStack(alignment: .center, spacing: 4) {
                            Text("Tax & Fees")
                                .font(.system(.caption, design: .rounded, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                            CurrencyText(amount: receipt.surchargeTotal,
                                         font: .system(.title3, design: .rounded, weight: .bold),
                                         color: Color.splitWarn)
                        }
                        Spacer()
                    }

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Total")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                        CurrencyText(amount: receipt.grandTotal,
                                     font: .system(.title2, design: .rounded, weight: .bold),
                                     color: Color.splitAccent)
                    }
                }

                // Accent bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.splitAccent.opacity(0.2))
                    .frame(height: 3)
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
                Text("AI scanned \(receipt.parsedTotal.map { $0.currencyString(code: tripCurrencyCode) } ?? "–"), computed \(receipt.grandTotal.currencyString(code: tripCurrencyCode)). Please review items.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.splitWarn.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.splitWarn.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func itemSection(title: String, count: Int, items: [LineItem], color: Color) -> some View {
        Section {
            ForEach(items) { item in
                LineItemRow(
                    item: item,
                    baseAmount: receipt.itemSubtotal,
                    onUpdate: { session.updateLineItem($0) },
                    onValidation: { invalid in
                        if invalid { invalidItems.insert(item.id) } else { invalidItems.remove(item.id) }
                    }
                )
                .padding(.vertical, 6)
                .listRowBackground(Color.splitCard)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Delete", role: .destructive) {
                        invalidItems.remove(item.id)
                        session.deleteLineItem(item)
                    }.tint(.red)
                }
            }
        } header: {
            HStack {
                Text("\(title) · \(count)").foregroundStyle(color)
                Spacer()
                CurrencyText(amount: items.reduce(Decimal(0)) { $0 + $1.amount }, font: .caption, color: .secondary)
            }.font(.system(.subheadline, design: .rounded, weight: .semibold)).textCase(nil)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "receipt")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.splitAccent)
                .padding(.bottom, 4)
            Text("Add your first item")
                .font(.system(.title3, design: .rounded, weight: .semibold))
            Text("Enter a name and price to start your receipt.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 20)
    }

    private var addItemButton: some View {
        Button {
            showAddItem = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                Text("Add Item")
                    .font(.system(.body, design: .rounded, weight: .semibold))
            }
            .foregroundStyle(Color.splitAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.splitAccent.opacity(0.08), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var continueButton: some View {
        Button {
            if let onContinue { onContinue() } else { session.navigate(to: .splitSetup) }
        } label: {
            HStack(spacing: 8) {
                Text("Continue")
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
            }
            .font(.system(.body, design: .rounded, weight: .bold))
            .foregroundStyle(.black.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                Capsule()
                    .fill(Color.splitAccent)
                    .shadow(color: Color.splitAccent.opacity(0.25), radius: 12, y: 4)
            )
        }
        .buttonStyle(.plain)
        .disabled((receipt.items.isEmpty && receipt.surcharges.isEmpty) || !invalidItems.isEmpty)
        .padding(.top, 4)
    }
}
