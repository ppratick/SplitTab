import SwiftUI

struct FeeToggleBar: View {
    @Binding var selection: FeeDistribution
    var accent: Color = .splitWarn

    var body: some View {
        HStack(spacing: 4) {
            ForEach(FeeDistribution.allCases) { option in
                toggleSegment(option)
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.04))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
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
                    .font(.system(size: 12, weight: .semibold))
                Text(option.rawValue)
                    .font(.system(.caption, design: .rounded, weight: .bold))
            }
            .foregroundStyle(selected ? .black.opacity(0.85) : .white.opacity(0.5))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                Capsule().fill(selected ? accent : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
