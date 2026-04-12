import SwiftUI

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var padding: CGFloat = 20
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// Prominent variant — brighter glass for hero elements
struct GlassHeroCard<Content: View>: View {
    var cornerRadius: CGFloat = 28
    var padding: CGFloat = 24
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// Glass capsule button
struct GlassCapsuleButton: View {
    let title: String
    let systemImage: String
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        if prominent {
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.splitBg)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(
                        Capsule().fill(LinearGradient(
                            colors: [Color.splitTeal, Color.splitAccent],
                            startPoint: .leading,
                            endPoint: .trailing))
                    )
            }
            .buttonStyle(.plain)
        } else {
            Button(action: action) {
                Label(title, systemImage: systemImage)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
    }
}
