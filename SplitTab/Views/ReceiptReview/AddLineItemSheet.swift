import SwiftUI

struct AddLineItemSheet: View {
    @Environment(\.tripCurrencyCode) private var tripCurrencyCode
    var baseAmount: Decimal
    var onAdd: (LineItem) -> Void

    @State private var name = ""
    @State private var amountText = ""
    @State private var percentText = ""
    @State private var inputMode: InputMode = .dollar
    @State private var category: LineItemCategory = .item
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    enum Field { case name, amount, percent }
    enum InputMode { case dollar, percentage }

    // MARK: - Computed

    private var supportsPct: Bool { category != .item }

    private var computedAmount: Decimal? {
        switch inputMode {
        case .dollar:
            return (try? TripCurrency.parse(amountText)).flatMap { $0 > 0 ? $0 : nil }
        case .percentage:
            guard let pct = Decimal(string: percentText), pct > 0 else { return nil }
            return Decimal.roundCurrency(baseAmount * pct / 100, code: tripCurrencyCode)
        }
    }

    private var computedPreview: String? {
        guard inputMode == .percentage, let amt = computedAmount else { return nil }
        return amt.currencyString(code: tripCurrencyCode)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && computedAmount.map { (try? TripCurrency.minor($0, tripCurrencyCode ?? "USD")) != nil } == true
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.splitBg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Item Details")
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(.secondary)

                                TextField("Item name", text: $name)
                                    .font(.system(.body, design: .rounded))
                                    .textInputAutocapitalization(.words)
                                    .focused($focusedField, equals: .name)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = inputMode == .dollar ? .amount : .percent }

                                Divider().overlay(Color.white.opacity(0.06))

                                if supportsPct {
                                    Picker("Input Mode", selection: $inputMode) {
                                        Text("Fixed").tag(InputMode.dollar)
                                        Text("% of subtotal").tag(InputMode.percentage)
                                    }
                                    .pickerStyle(.segmented)
                                    .onChange(of: inputMode) { _, newMode in
                                        switch newMode {
                                        case .dollar:
                                            if let pct = Decimal(string: percentText), pct > 0, baseAmount > 0 {
                                                let v = Decimal.roundCurrency(baseAmount * pct / 100, code: tripCurrencyCode)
                                                amountText = NSDecimalNumber(decimal: v).stringValue
                                            }
                                        case .percentage:
                                            if let amt = Decimal(string: amountText), amt > 0, baseAmount > 0 {
                                                let v = Decimal.roundToTwo(amt / baseAmount * 100)
                                                percentText = NSDecimalNumber(decimal: v).stringValue
                                            }
                                        }
                                    }

                                    Divider().overlay(Color.white.opacity(0.06))
                                }

                                if inputMode == .dollar || !supportsPct {
                                    HStack {
                                        Text("Amount")
                                            .font(.system(.body, design: .rounded))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        HStack(spacing: 0) {
                                            Text(tripCurrencyCode ?? "$")
                                                .foregroundStyle(.secondary)
                                                .font(.system(.body, design: .rounded, weight: .semibold))
                                            TextField("0.00", text: $amountText)
                                                .font(.system(.body, design: .rounded, weight: .semibold))
                                                .multilineTextAlignment(.trailing)
                                                .keyboardType(.decimalPad)
                                                .focused($focusedField, equals: .amount)
                                                .frame(width: 80)
                                        }
                                    }
                                } else {
                                    HStack {
                                        Text("Percentage")
                                            .font(.system(.body, design: .rounded))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        HStack(spacing: 4) {
                                            TextField("0", text: $percentText)
                                                .font(.system(.body, design: .rounded, weight: .semibold))
                                                .multilineTextAlignment(.trailing)
                                                .keyboardType(.decimalPad)
                                                .focused($focusedField, equals: .percent)
                                                .frame(width: 60)
                                            Text("%")
                                                .foregroundStyle(.secondary)
                                                .font(.system(.body, design: .rounded))
                                        }
                                    }

                                    if let preview = computedPreview {
                                        HStack {
                                            Text("Equals")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text(preview)
                                                .font(.system(.caption, design: .rounded, weight: .semibold))
                                                .foregroundStyle(Color.splitAccent)
                                        }
                                        .padding(.top, 2)
                                    } else if !percentText.isEmpty {
                                        HStack {
                                            Spacer()
                                            Text(baseAmount > 0 ? "Enter a valid %" : "No subtotal yet")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }

                        GlassCard(padding: 16) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Category")
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(.secondary)

                                LazyVGrid(
                                    columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                                    spacing: 10
                                ) {
                                    ForEach(LineItemCategory.allCases) { cat in
                                        categoryChip(cat)
                                    }
                                }
                                .onChange(of: category) { _, newCat in
                                    let def = newCat.defaultName
                                    if !def.isEmpty { name = def }
                                }
                            }
                        }

                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .keyboardDismissButton()
        .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .glassEffect(.regular.interactive(), in: Circle())
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        commitAdd()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(canSave ? .black.opacity(0.8) : Color.secondary)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle().fill(canSave ? Color.splitAccent : Color.white.opacity(0.1))
                            )
                    }
                    .disabled(!canSave)
                }
            }
        }
        .onAppear { focusedField = .name }
    }

    private func categoryChip(_ cat: LineItemCategory) -> some View {
        let selected = category == cat
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                category = cat
                if cat == .item { inputMode = .dollar }
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: cat.systemImage)
                    .font(.system(size: 18, weight: .medium))
                Text(cat.rawValue)
                    .font(.caption2)
            }
            .foregroundStyle(selected ? .black.opacity(0.8) : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Color.splitAccent : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(selected ? Color.clear : Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func commitAdd() {
        guard let amt = computedAmount else { return }
        let finalAmount = category == .discount ? (amt > 0 ? -amt : amt) : amt

        let pct: Decimal?
        if category != .item {
            if inputMode == .percentage, let p = Decimal(string: percentText), p > 0 {
                pct = p
            } else if baseAmount > 0 {
                pct = Decimal.roundToTwo(abs(amt) / baseAmount * 100)
            } else {
                pct = nil
            }
        } else {
            pct = nil
        }

        let item = LineItem(name: name, amount: finalAmount, category: category, sourcePercent: pct)
        onAdd(item)
        dismiss()
    }
}
