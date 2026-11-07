import SwiftUI

struct ReceiptReviewView: View {
    var onContinue: (() -> Void)? = nil
    @Environment(\.tripCurrencyCode) private var tripCurrencyCode
    @Environment(SplitSessionViewModel.self) private var session
    @State private var showAddItem = false
    @State private var showCurrency = false
    @State private var targetCurrency = "USD"
    @State private var conversionRate = ""
    @State private var conversionError: String?
    @State private var invalidItems: Set<UUID> = []

    private var receipt: ReceiptData { session.receipt ?? .empty }
    private var originalReceipt: ReceiptData { receipt.editableReceipt }
    private var originalCurrency: String { originalReceipt.currencyCode ?? session.currencyCode }
    private var calculatedCurrency: String? {
        session.pendingReceiptCurrency ?? (receipt.original != nil ? session.currencyCode : nil)
    }
    private func rateText(for target: String) -> String {
        let value = target == receipt.conversion?.targetCurrency ? receipt.conversion?.rate : originalReceipt.inferredRate(to: target)
        return value.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
    }

    var body: some View {
        ZStack {
            Color.splitBg.ignoresSafeArea()

            List {
                    Section {
                        currencyDetails
                            .listRowBackground(Color.clear).listRowSeparator(.hidden)
                    }
                    if !receipt.items.isEmpty || !receipt.surcharges.isEmpty || !receipt.discounts.isEmpty {
                        Section { summaryCard.listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden) }
                    }

                    if let discrepancy = receipt.totalDiscrepancy {
                        discrepancyBanner(discrepancy: discrepancy)
                    }

                    if !receipt.items.isEmpty {
                        itemSection(title: "Items", count: originalReceipt.items.count, items: originalReceipt.items, color: Color.splitAccent)
                    }

                    if !receipt.surcharges.isEmpty {
                        itemSection(title: "Tax & Fees", count: originalReceipt.surcharges.count, items: originalReceipt.surcharges, color: Color.splitWarn)
                    }

                    if !receipt.discounts.isEmpty {
                        itemSection(title: "Discounts", count: originalReceipt.discounts.count, items: originalReceipt.discounts, color: Color.splitViolet)
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
                    if let pending = session.pendingReceiptCurrency {
                        targetCurrency = pending
                        conversionRate = rateText(for: pending)
                        conversionError = nil
                        showCurrency = true
                    } else if let onContinue { onContinue() } else { session.navigate(to: .splitSetup) }
                }
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.splitAccent)
                .disabled((receipt.items.isEmpty && receipt.surcharges.isEmpty) || !invalidItems.isEmpty)
            }
        }
        .sheet(isPresented: $showCurrency) {
            NavigationStack {
                Form {
                    Picker("Split currency", selection: $targetCurrency) {
                        ForEach(TripCurrency.codes, id: \.self) { Text($0).tag($0) }
                    }
                    if targetCurrency != originalCurrency {
                        HStack {
                            Text("1 \(originalCurrency) =")
                            TextField("Rate", text: $conversionRate).keyboardType(.decimalPad)
                            Text(targetCurrency)
                        }
                        if originalReceipt.inferredRate(to: targetCurrency) != nil {
                            Text("Rate inferred from the printed receipt totals. You can edit it.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let conversionError { Text(conversionError).foregroundStyle(Color.splitWarn) }
                }
                .tripStyle().navigationTitle("Receipt currency")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showCurrency = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            do {
                                let rate = targetCurrency == originalCurrency ? nil : try TripCurrency.parse(conversionRate)
                                try session.convertReceipt(to: targetCurrency, rate: rate)
                                showCurrency = false
                            } catch { conversionError = error.localizedDescription }
                        }
                    }
                }
                .onChange(of: targetCurrency) { _, target in
                    conversionRate = rateText(for: target)
                    conversionError = nil
                }
            }.preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showAddItem) {
            AddLineItemSheet(baseAmount: originalReceipt.itemSubtotal) { item in
                session.addLineItem(item)
            }.environment(\.tripCurrencyCode, originalCurrency)
        }
        .preferredColorScheme(.dark)
        .tripError(Binding(get: { session.calculationError }, set: { session.calculationError = $0 }))
    }

    // MARK: - Subviews

    private var currencyDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Split currency").foregroundStyle(.secondary)
                Spacer()
                Button(session.pendingReceiptCurrency ?? session.currencyCode, systemImage: "arrow.left.arrow.right") {
                    targetCurrency = session.pendingReceiptCurrency ?? session.currencyCode
                    conversionRate = rateText(for: targetCurrency)
                    conversionError = nil
                    showCurrency = true
                }.tint(Color.splitAccent)
            }
            if let pending = session.pendingReceiptCurrency {
                Text("Prices are in \(session.currencyCode). Enter the rate to split in \(pending).")
                    .font(.caption).foregroundStyle(Color.splitWarn)
            } else if let conversion = receipt.conversion, receipt.original != nil {
                Button {
                    targetCurrency = session.currencyCode
                    conversionRate = rateText(for: targetCurrency)
                    conversionError = nil
                    showCurrency = true
                } label: {
                    Text("1 \(originalCurrency) = \(conversion.rateLabel) \(session.currencyCode) · Edit rate")
                        .font(.caption)
                }.tint(Color.splitAccent)
                Text("Edit the \(originalCurrency) prices below. \(session.currencyCode) updates automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let conversion = receipt.conversion, receipt.original == nil {
                Text("Converted from \(conversion.sourceCurrency). Rescan to edit the original prices.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let tax = receipt.includedTax, tax > 0 {
                Text("Tax included in prices: \(TripCurrency.formatDecimal(tax, session.currencyCode))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 12) {
            if let calculatedCurrency {
                receiptSummary(originalReceipt, heading: "Original · \(originalCurrency)")
                    .environment(\.tripCurrencyCode, originalCurrency)
                if session.pendingReceiptCurrency == nil {
                    receiptSummary(receipt, heading: "Calculated · \(calculatedCurrency)")
                        .environment(\.tripCurrencyCode, calculatedCurrency)
                } else {
                    Text("Calculated · \(calculatedCurrency) — enter an exchange rate")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20)
                }
            } else { receiptSummary(receipt) }
        }
    }

    private func receiptSummary(_ value: ReceiptData, heading: String? = nil) -> some View {
        GlassCard(cornerRadius: 24, padding: 22) {
            VStack(spacing: 16) {
                if let heading {
                    Text(heading).font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Subtotal")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                        CurrencyText(amount: value.itemSubtotal,
                                     font: .system(.title3, design: .rounded, weight: .bold))
                    }
                    Spacer()

                    if value.surchargeTotal > 0 {
                        VStack(alignment: .center, spacing: 4) {
                            Text("Tax & Fees")
                                .font(.system(.caption, design: .rounded, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                            CurrencyText(amount: value.surchargeTotal,
                                         font: .system(.title3, design: .rounded, weight: .bold),
                                         color: Color.splitWarn)
                        }
                        Spacer()
                    }

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Total")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                        CurrencyText(amount: value.grandTotal,
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
                    baseAmount: originalReceipt.itemSubtotal,
                    convertedAmount: session.pendingReceiptCurrency == nil && calculatedCurrency != nil ? (receipt.items + receipt.surcharges + receipt.discounts).first { $0.id == item.id }?.amount : nil,
                    convertedCurrency: calculatedCurrency,
                    onUpdate: { session.updateLineItem($0) },
                    onValidation: { invalid in
                        if invalid || session.calculationError != nil { invalidItems.insert(item.id) } else { invalidItems.remove(item.id) }
                    }
                )
                .environment(\.tripCurrencyCode, originalCurrency)
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
                Text(TripCurrency.formatDecimal(items.reduce(Decimal(0)) { $0 + $1.amount }, originalCurrency))
                    .font(.caption).foregroundStyle(.secondary)
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
