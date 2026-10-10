import SwiftUI

struct AssignableItemRow: View {
    @Environment(\.tripCurrencyCode) private var tripCurrencyCode
    let item: LineItem
    let people: [Person]
    let assignedPeople: [Person]
    var onToggle: (UUID) -> Void
    var onDelete: (() -> Void)? = nil
    @State private var isExpanded = true
    private var isAssigned: Bool { !assignedPeople.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 14) {
                    // Left accent indicator
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isAssigned ? Color.splitAccent : Color.white.opacity(0.1))
                        .frame(width: 3, height: 32)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name)
                            .font(.system(.body, design: .rounded, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if !assignedPeople.isEmpty {
                            Text(assignedPeople.map(\.name).joined(separator: ", "))
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(Color.splitAccent.opacity(0.7))
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    if assignedPeople.isEmpty {
                        Text("Unassigned")
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.35))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(Color.white.opacity(0.06))
                            )
                    } else {
                        StackedAvatars(people: assignedPeople, size: 26)
                    }

                    Text(item.amount.currencyString(code: tripCurrencyCode))
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .frame(minWidth: 58, alignment: .trailing)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.25))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().overlay(Color.white.opacity(0.06))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(people) { person in
                            PersonChip(
                                person: person,
                                isSelected: assignedPeople.contains(where: { $0.id == person.id }),
                                action: { onToggle(person.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
