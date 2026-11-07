import SwiftUI

/// Compact, directly editable receipt row shared by bills and trips.
struct LineItemRow: View {
    @Environment(\.tripCurrencyCode) private var currency
    let item: LineItem
    var baseAmount: Decimal = 0
    var convertedAmount: Decimal?
    var convertedCurrency: String?
    var onUpdate: (LineItem) -> Void
    var onValidation: (Bool) -> Void
    @State private var name: String
    @State private var price: String
    @State private var percent = ""
    @State private var showPercent = false
    @FocusState private var focus: Field?
    private enum Field { case name, price }

    init(item: LineItem, baseAmount: Decimal = 0, convertedAmount: Decimal? = nil, convertedCurrency: String? = nil, onUpdate: @escaping (LineItem) -> Void, onValidation: @escaping (Bool) -> Void) {
        self.item = item; self.baseAmount = baseAmount
        self.convertedAmount = convertedAmount; self.convertedCurrency = convertedCurrency
        self.onUpdate = onUpdate; self.onValidation = onValidation
        _name = State(initialValue: item.name)
        _price = State(initialValue: NSDecimalNumber(decimal: abs(item.amount)).stringValue)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.category.systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(item.category == .discount ? Color.splitViolet : (item.category == .item ? Color.splitAccent : Color.splitWarn))
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                TextField("Item name", text: Binding(get: { name }, set: { name = $0; update() }))
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .textInputAutocapitalization(.words).focused($focus, equals: .name)
                    .accessibilityIdentifier("receipt.name.\(item.id)")
                    .submitLabel(.done).onSubmit { focus = nil }
                HStack(spacing: 4) {
                    Text(item.category.rawValue)
                    if let pct = item.sourcePercent { Text("· \(pct.digitsString)%") }
                    if item.isLowConfidence { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                }.font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 3) {
                    Text((item.category == .discount ? "− " : "") + (currency ?? "USD"))
                        .font(.caption2).foregroundStyle(.secondary)
                    TextField("Price", text: Binding(get: { price }, set: { price = $0; update() }))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .font(.system(.body, design: .rounded, weight: .semibold)).monospacedDigit()
                        .focused($focus, equals: .price)
                        .frame(width: 80)
                        .accessibilityIdentifier("receipt.price.\(item.id)")
                }
                if let convertedCurrency {
                    Text(convertedAmount.map { TripCurrency.formatDecimal($0, convertedCurrency) } ?? "\(convertedCurrency) —")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.splitAccent).monospacedDigit()
                        .accessibilityIdentifier("receipt.converted.\(item.id)")
                }
            }

        }
        .onChange(of: item.amount) { _, amount in
            if focus != .price { price = NSDecimalNumber(decimal: abs(amount)).stringValue }
        }
        .contextMenu {
            if item.category != .item && item.category != .unknown {
                Button("Edit percentage") {
                    percent = item.sourcePercent.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
                    showPercent = true
                }
            }
        }
        .sheet(isPresented: $showPercent) {
            NavigationStack {
                Form {
                    TextField("Percent of subtotal", text: $percent).keyboardType(.decimalPad)
                    if let value = percentageAmount { Text(value.currencyString(code: currency)) }
                }.keyboardDismissButton().navigationTitle("\(item.name) percentage")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showPercent = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            guard let value = percentageAmount, let pct = Decimal(string: percent) else { return }
                            var updated = item
                            updated.amount = item.category == .discount ? -value : value
                            updated.sourcePercent = pct
                            price = NSDecimalNumber(decimal: value).stringValue
                            onUpdate(updated); onValidation(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty); showPercent = false
                        }.disabled(percentageAmount == nil)
                    }
                }
            }.presentationDetents([.height(260)])
        }
    }

    private var percentageAmount: Decimal? {
        guard let value = Decimal(string: percent), value > 0, baseAmount > 0 else { return nil }
        let amount = Decimal.roundCurrency(baseAmount * value / 100, code: currency)
        guard amount > 0, (try? TripCurrency.minor(amount, currency ?? "USD")) != nil else { return nil }
        return amount
    }
    private func update() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, let amount = try? TripCurrency.parse(price), amount > 0,
              (try? TripCurrency.minor(amount, currency ?? "USD")) != nil else {
            onValidation(true); return
        }
        var updated = item
        updated.name = cleanName
        updated.amount = item.category == .discount ? -amount : amount
        if amount != abs(item.amount) {
            updated.sourcePercent = item.category != .item && baseAmount > 0 ? Decimal.roundToTwo(amount / baseAmount * 100) : nil
        }
        onUpdate(updated); onValidation(false)
    }
}
