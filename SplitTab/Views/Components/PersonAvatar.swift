import SwiftUI

struct PersonAvatar: View {
    let person: Person
    var size: CGFloat = 36
    var showName: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(person.avatarColor.gradient)
                    .frame(width: size, height: size)
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.7))
            }
            if showName {
                Text(person.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: size + 8)
            }
        }
    }

    private var initials: String {
        let parts = person.name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1)) + String(parts[1].prefix(1))
        }
        return String(person.name.prefix(2)).uppercased()
    }
}

// Stacked overlapping avatars (e.g., showing assignees on an item row)
struct StackedAvatars: View {
    let people: [Person]
    var size: CGFloat = 26
    var maxVisible: Int = 3

    var body: some View {
        let visible = Array(people.prefix(maxVisible))
        let overflow = people.count - maxVisible

        HStack(spacing: 0) {
            ZStack {
                ForEach(Array(visible.enumerated()), id: \.element.id) { idx, person in
                    Circle()
                        .fill(person.avatarColor.gradient)
                        .frame(width: size, height: size)
                        .overlay(Circle().strokeBorder(Color.splitBg, lineWidth: 1.5))
                        .offset(x: CGFloat(idx) * (size * 0.55))
                }
                if overflow > 0 {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: size, height: size)
                            .overlay(Circle().strokeBorder(Color.splitBg, lineWidth: 1.5))
                        Text("+\(overflow)")
                            .font(.system(size: size * 0.32, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .offset(x: CGFloat(visible.count) * (size * 0.55))
                }
            }
            .frame(width: size + CGFloat(min(people.count, maxVisible + (overflow > 0 ? 1 : 0)) - 1) * (size * 0.55), height: size)
        }
    }
}
