import SwiftUI

struct PersonChip: View {
    let person: Person
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(person.name)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .black.opacity(0.85) : .primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? person.avatarColor : Color.white.opacity(0.04))
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                isSelected ? Color.clear : Color.white.opacity(0.08),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: isSelected ? person.avatarColor.opacity(0.2) : .clear, radius: 6, y: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(person.name)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
    }

    private var initials: String {
        let parts = person.name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1)) + String(parts[1].prefix(1))
        }
        return String(person.name.prefix(2)).uppercased()
    }
}
