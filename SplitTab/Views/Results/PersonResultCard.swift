import SwiftUI

struct PersonResultCard: View {
    @Environment(\.tripCurrencyCode) private var currencyCode
    let result: PersonResult
    let splitMode: SplitMode
    @State private var isExpanded = false
    @State private var copied = false
    @State private var copyError: String?

    private var personColor: Color {
        Person.palette[result.avatarColorIndex % Person.palette.count]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Colored accent bar at top
            RoundedRectangle(cornerRadius: 2)
                .fill(personColor.opacity(0.5))
                .frame(height: 3)
                .padding(.horizontal, 20)
                .padding(.top, 2)

            VStack(spacing: 0) {
                HStack(spacing: 14) {

                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.name)
                            .font(.system(.body, design: .rounded, weight: .bold))
                            .foregroundStyle(.primary)
                        Text(isExpanded ? "Breakdown" : "Tap to expand")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.white.opacity(0.35))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        CurrencyText(
                            amount: result.total,
                            font: .system(.title2, design: .rounded, weight: .bold),
                            color: personColor
                        )
                    }

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.3))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                }

                HStack(spacing: 16) {
                    Button("Copy total", systemImage: "doc.on.doc") { copy(breakdown: false) }
                        .accessibilityIdentifier("copy.person.total.\(result.id)")
                    Button("Copy breakdown", systemImage: "list.bullet.clipboard") { copy(breakdown: true) }
                        .accessibilityIdentifier("copy.person.breakdown.\(result.id)")
                    if copied { Image(systemName: "checkmark").accessibilityLabel("Copied") }
                }
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .tint(Color.splitAccent).buttonStyle(.plain)
                .padding(.horizontal, 18).padding(.bottom, 14)

                if isExpanded {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white.opacity(0.05))
                        .frame(height: 1)
                        .padding(.horizontal, 18)

                    breakdownSection
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .tripError($copyError)
    }

    private func copy(breakdown: Bool) {
        do {
            try ShareClipboard.copy(SplitCopyText.person(result, currency: currencyCode ?? "USD", breakdown: breakdown))
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        } catch { copyError = error.localizedDescription }
    }

    // MARK: - Breakdown

    private var breakdownSection: some View {
        VStack(spacing: 0) {
            if splitMode == .itemized && !result.assignedItems.isEmpty {
                VStack(spacing: 0) {
                    sectionHeader("Items", color: Color.splitAccent)
                    ForEach(result.assignedItems, id: \.item.id) { entry in
                        breakdownRow(
                            label: entry.item.name,
                            amount: entry.shareAmount,
                            dimmed: false
                        )
                    }
                }
            }

            RoundedRectangle(cornerRadius: 1)
                .fill(Color.white.opacity(0.04))
                .frame(height: 1)
                .padding(.horizontal, 18)

            breakdownRow(label: "Subtotal", amount: result.itemSubtotal, bold: true)

            if result.feeShare != 0 {
                breakdownRow(label: "Tax & Fees", amount: result.feeShare, color: Color.splitWarn)
            }

            if result.discountShare != 0 {
                breakdownRow(label: "Discounts", amount: result.discountShare, color: Color.splitViolet)
            }

            RoundedRectangle(cornerRadius: 1)
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
                .padding(.horizontal, 18)

            let adjustment = result.total - result.itemSubtotal - result.feeShare - result.discountShare
            if adjustment != 0 { breakdownRow(label: "Rounding adjustment", amount: adjustment) }

            HStack {
                Text("Total")
                    .font(.system(.body, design: .rounded, weight: .bold))
                Spacer()
                CurrencyText(
                    amount: result.total,
                    font: .system(.body, design: .rounded, weight: .bold),
                    color: personColor
                )
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func sectionHeader(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .foregroundStyle(color.opacity(0.7))
            .textCase(.uppercase)
            .tracking(0.3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func breakdownRow(label: String, amount: Decimal, bold: Bool = false, dimmed: Bool = false, color: Color = .primary) -> some View {
        HStack {
            Text(label)
                .font(bold ? .system(.subheadline, design: .rounded, weight: .semibold) : .system(.caption, design: .rounded))
                .foregroundStyle(dimmed ? .secondary : .primary)
                .lineLimit(1)
            Spacer()
            CurrencyText(amount: amount, font: bold ? .system(.subheadline, design: .rounded, weight: .semibold) : .system(.caption, design: .rounded), color: color)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
    }

    private var fakePerson: Person {
        Person(id: result.id, name: result.name, colorIndex: result.avatarColorIndex)
    }
}
