import SwiftUI

/// Shared primary split interaction for standalone receipts and trip expenses.
struct SplitMethodCards: View {
    var selection: SplitMode?
    var onSelect: (SplitMode) -> Void
    var body: some View {
        HStack(spacing: 12) {
            ForEach([SplitMode.even, .itemized]) { mode in
                let selected = selection == mode
                let accent: Color = mode == .even ? .splitAccent : .splitViolet
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { onSelect(mode) } } label: {
                    VStack(spacing: 12) {
                        Image(systemName: mode.systemImage)
                            .font(.system(size: 28, weight: .medium))
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(selected ? Color.clear : accent.opacity(0.1)))
                        Text(mode == .even ? "Even split" : "By items")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                        Text(mode == .even ? "Share the total equally" : "Pay for what you had")
                            .font(.system(.caption2, design: .rounded))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(selected ? Color.black.opacity(0.85) : accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18).padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 20).fill(selected ? accent : Color.white.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(selected ? 0 : 0.07)))
                }.buttonStyle(.plain)
                .accessibilityIdentifier(mode == .even ? "split.even" : "split.items")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}
