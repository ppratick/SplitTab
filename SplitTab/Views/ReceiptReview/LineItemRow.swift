import SwiftUI

struct LineItemRow: View {
    let item: LineItem
    var baseAmount: Decimal = 0
    @Binding var editingItemID: UUID?
    var onUpdate: (LineItem) -> Void
    var onDelete: () -> Void

    @State private var editName: String = ""
    @State private var editAmountText: String = ""
    @State private var editPercentText: String = ""
    @State private var editInputMode: EditInputMode = .dollar

    enum EditInputMode { case dollar, percentage }

    // MARK: - Derived state

    private var isEditing: Bool { editingItemID == item.id }
    private var supportsPct: Bool { item.category != .item }

    private var computedEditAmount: Decimal? {
        switch editInputMode {
        case .dollar:
            return Decimal(string: editAmountText).flatMap { $0 != 0 ? $0 : nil }
        case .percentage:
            guard let pct = Decimal(string: editPercentText), pct > 0 else { return nil }
            return Decimal.roundToTwo(baseAmount * pct / 100)
        }
    }

    private var canCommit: Bool { !editName.isEmpty && computedEditAmount != nil }

    private var livePercentPreview: String? {
        guard supportsPct, baseAmount > 0 else { return nil }
        if let amt = Decimal(string: editAmountText), amt != 0 {
            let pct = Decimal.roundToTwo(abs(amt) / baseAmount * 100)
            return "\(pct.digitsString)%"
        }
        return item.sourcePercent.map { "\($0.digitsString)%" }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if isEditing {
                editingRow
            } else {
                displayRow
            }
        }
        .onChange(of: editingItemID) { oldValue, newValue in
            if oldValue == item.id, newValue != item.id {
                saveCurrentEdit()
            }
        }
    }

    // MARK: - Display Row

    private var displayRow: some View {
        HStack(spacing: 12) {
            Image(systemName: item.category.systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(categoryColor)
                .frame(width: 28, height: 28)
                .background(Circle().fill(categoryColor.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if item.isLowConfidence {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                HStack(spacing: 4) {
                    Text(item.category.rawValue)
                    if let pct = item.sourcePercent {
                        Text("· \(pct.digitsString)%")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(item.amount.currencyString)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(item.amount < 0 ? Color.splitAccent : .primary)
                .monospacedDigit()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.05)))
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture { handleTap() }
    }

    // MARK: - Editing Row

    private var editingRow: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: item.category.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(categoryColor)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(categoryColor.opacity(0.12)))
                Text(editName.isEmpty ? item.name : editName)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { commitEdit() }

            Divider().overlay(Color.white.opacity(0.06))

            HStack {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .leading)
                TextField("Item name", text: $editName)
                    .font(.system(.body, design: .rounded))
                    .textInputAutocapitalization(.words)
                    .multilineTextAlignment(.trailing)
            }

            Divider().overlay(Color.white.opacity(0.06))

            if supportsPct {
                Picker("Input", selection: $editInputMode) {
                    Text("$ Fixed").tag(EditInputMode.dollar)
                    Text("% of subtotal").tag(EditInputMode.percentage)
                }
                .pickerStyle(.segmented)
                .onChange(of: editInputMode) { _, newMode in
                    switch newMode {
                    case .dollar:
                        if let pct = Decimal(string: editPercentText), pct > 0, baseAmount > 0 {
                            let v = Decimal.roundToTwo(baseAmount * pct / 100)
                            editAmountText = NSDecimalNumber(decimal: v).stringValue
                        }
                    case .percentage:
                        if let amt = Decimal(string: editAmountText), amt != 0, baseAmount > 0 {
                            let v = Decimal.roundToTwo(abs(amt) / baseAmount * 100)
                            editPercentText = NSDecimalNumber(decimal: v).stringValue
                        }
                    }
                }

                Divider().overlay(Color.white.opacity(0.06))
            }

            if editInputMode == .dollar || !supportsPct {
                HStack {
                    Text("Amount")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .leading)
                    Spacer()
                    HStack(spacing: 0) {
                        Text("$")
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $editAmountText)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .frame(width: 90)
                    }
                }
                if let preview = livePercentPreview {
                    HStack {
                        Spacer()
                        Text("\(preview) of subtotal")
                            .font(.caption2)
                            .foregroundStyle(Color.splitAccent.opacity(0.7))
                            .animation(.default, value: preview)
                    }
                }
            } else {
                HStack {
                    Text("Percent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .leading)
                    Spacer()
                    HStack(spacing: 0) {
                        TextField("0", text: $editPercentText)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .frame(width: 60)
                        Text("%")
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                if let preview = computedEditAmount {
                    HStack {
                        Spacer()
                        Text("= \(preview.currencyString)")
                            .font(.caption)
                            .foregroundStyle(Color.splitAccent)
                    }
                }
            }

            Divider().overlay(Color.white.opacity(0.06))

            HStack(spacing: 10) {
                Button {
                    cancelEdit()
                } label: {
                    Text("Cancel")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Capsule())

                Button {
                    commitEdit()
                } label: {
                    Text("Save")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(canCommit ? .black.opacity(0.8) : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            Capsule().fill(canCommit ? Color.splitAccent : Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canCommit)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private var categoryColor: Color {
        switch item.category {
        case .item:     return Color.splitAccent
        case .tax:      return Color.splitWarn
        case .tip:      return Color(red: 0.93, green: 0.46, blue: 0.46)
        case .fee:      return Color(red: 0.56, green: 0.78, blue: 0.94)
        case .discount: return Color.splitAccent
        case .unknown:  return .secondary
        }
    }

    private func handleTap() {
        if isEditing {
            commitEdit()
        } else {
            beginEdit()
            editingItemID = item.id
        }
    }

    private func beginEdit() {
        editName = item.name
        if let pct = item.sourcePercent, item.category != .item {
            editInputMode = .percentage
            editPercentText = pct.digitsString
            editAmountText = NSDecimalNumber(decimal: abs(item.amount)).stringValue
        } else {
            editInputMode = .dollar
            editAmountText = NSDecimalNumber(decimal: abs(item.amount)).stringValue
            editPercentText = ""
        }
    }

    private func saveCurrentEdit() {
        guard !editName.isEmpty else { return }

        let rawAmt: Decimal
        let pct: Decimal?

        if editInputMode == .percentage, let p = Decimal(string: editPercentText), p > 0 {
            rawAmt = Decimal.roundToTwo(baseAmount * p / 100)
            pct = p
        } else if let a = Decimal(string: editAmountText), a != 0 {
            rawAmt = a
            pct = (supportsPct && baseAmount > 0)
                ? Decimal.roundToTwo(abs(a) / baseAmount * 100)
                : nil
        } else {
            return
        }

        let finalAmount = item.category == .discount ? (rawAmt > 0 ? -rawAmt : rawAmt) : rawAmt
        var updated = item
        updated.name = editName
        updated.amount = finalAmount
        updated.sourcePercent = pct
        onUpdate(updated)
    }

    private func commitEdit() {
        saveCurrentEdit()
        editingItemID = nil
    }

    private func cancelEdit() {
        editName = item.name
        editAmountText = NSDecimalNumber(decimal: abs(item.amount)).stringValue
        editPercentText = item.sourcePercent.map { $0.digitsString } ?? ""
        editInputMode = item.sourcePercent != nil && item.category != .item ? .percentage : .dollar
        editingItemID = nil
    }
}
