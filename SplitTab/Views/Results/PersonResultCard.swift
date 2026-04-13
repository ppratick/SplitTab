import SwiftUI

struct PersonResultCard: View {
    let result: PersonResult
    let splitMode: SplitMode
    @State private var isExpanded = false
    @State private var copied = false

    var body: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    PersonAvatar(person: fakePerson, size: 44)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.name)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Tap to see breakdown")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        CurrencyText(
                            amount: result.total,
                            font: .system(.title2, design: .rounded, weight: .bold),
                            color: fakePerson.avatarColor
                        )
                        Text("total")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        UIPasteboard.general.string = result.total.currencyString
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { copied = false }
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(copied ? Color.splitAccent : Color.secondary)
                            .frame(width: 30, height: 30)
                            .glassEffect(.regular.interactive(), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
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

                if isExpanded {
                    Divider().overlay(Color.white.opacity(0.06))
                    breakdownSection
                }
            }
        }
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

            Divider().overlay(Color.white.opacity(0.05)).padding(.horizontal, 18)

            breakdownRow(label: "Subtotal", amount: result.itemSubtotal, bold: true)

            if result.feeShare != 0 {
                breakdownRow(label: "Tax & Fees", amount: result.feeShare, color: Color.splitWarn)
            }

            if result.discountShare != 0 {
                breakdownRow(label: "Discounts", amount: result.discountShare, color: Color.splitAccent)
            }

            Divider().overlay(Color.white.opacity(0.08)).padding(.horizontal, 18)

            HStack {
                Text("Total")
                    .font(.system(.body, design: .rounded, weight: .bold))
                Spacer()
                CurrencyText(
                    amount: result.total,
                    font: .system(.body, design: .rounded, weight: .bold),
                    color: fakePerson.avatarColor
                )
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func sectionHeader(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .foregroundStyle(color)
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
