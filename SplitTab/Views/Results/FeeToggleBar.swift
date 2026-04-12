import SwiftUI

struct FeeToggleBar: View {
    @Binding var selection: FeeDistribution

    var body: some View {
        HStack(spacing: 0) {
            ForEach(FeeDistribution.allCases) { option in
                toggleSegment(option)
            }
        }
        .background(
            Capsule()
                .fill(.regularMaterial)
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        )
    }

    private func toggleSegment(_ option: FeeDistribution) -> some View {
        let selected = selection == option
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selection = option
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: option.systemImage)
                    .font(.system(size: 13, weight: .medium))
                Text(option.rawValue)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
            }
            .foregroundStyle(selected ? Color.splitBg : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                Capsule()
                    .fill(selected
                          ? AnyShapeStyle(LinearGradient(colors: [Color.splitTeal, Color.splitAccent], startPoint: .leading, endPoint: .trailing))
                          : AnyShapeStyle(Color.clear))
            )
        }
        .buttonStyle(.plain)
    }
}
