import SwiftUI

struct AssignableItemRow: View {
    let item: LineItem
    let people: [Person]
    let assignedPeople: [Person]
    var onToggle: (UUID) -> Void
    /// Shared across all rows — whichever item's ID is set is the one expanded.
    @Binding var expandedItemID: UUID?

    private var isExpanded: Bool { expandedItemID == item.id }

    var body: some View {
        VStack(spacing: 0) {
            // Main row
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    expandedItemID = isExpanded ? nil : item.id
                }
            } label: {
                HStack(spacing: 14) {
                    // Item info
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name)
                            .font(.system(.body, design: .rounded, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if !assignedPeople.isEmpty {
                            Text(assignedPeople.map(\.name).joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    // Stacked avatars or unassigned badge
                    if assignedPeople.isEmpty {
                        Text("Unassigned")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(Color.white.opacity(0.07))
                            )
                    } else {
                        StackedAvatars(people: assignedPeople, size: 28)
                    }

                    // Amount
                    Text(item.amount.currencyString)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .frame(minWidth: 58, alignment: .trailing)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            // Expanded chip picker
            if isExpanded {
                Divider().overlay(Color.white.opacity(0.08))

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
