import SwiftUI

struct ItemAssignmentView: View {
    @Environment(SplitSessionViewModel.self) private var session
    @State private var expandedItemID: UUID? = nil

    private var items: [LineItem] { session.receipt?.items ?? [] }

    var body: some View {
        ZStack {
            Color.splitBg.ignoresSafeArea()
            LinearGradient(
                colors: [Color(red: 0.72, green: 0.46, blue: 1.0).opacity(0.07), Color.clear],
                startPoint: .top, endPoint: .center
            ).ignoresSafeArea()

            VStack(spacing: 0) {
                // Unassigned warning banner
                if session.unassignedFoodItemCount > 0 {
                    unassignedBanner
                }

                ScrollView {
                    VStack(spacing: 16) {
                        // Instructions card
                        instructionCard

                        // Items
                        if !items.isEmpty {
                            GlassCard(padding: 0) {
                                VStack(spacing: 0) {
                                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                                        AssignableItemRow(
                                            item: item,
                                            people: session.people,
                                            assignedPeople: session.assignedPeople(for: item.id),
                                            onToggle: { personId in
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                    session.toggleAssignment(itemId: item.id, personId: personId)
                                                }
                                            },
                                            onDelete: {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                    if expandedItemID == item.id { expandedItemID = nil }
                                                    session.deleteLineItem(item)
                                                }
                                            },
                                            expandedItemID: $expandedItemID
                                        )

                                        if idx < items.count - 1 {
                                            Divider().overlay(Color.white.opacity(0.07))
                                        }
                                    }
                                }
                            }
                        } else {
                            emptyState
                        }

                        // Surcharges info
                        if let surcharges = session.receipt?.surcharges, !surcharges.isEmpty {
                            surchargesInfo(surcharges: surcharges)
                        }

                        // See Results button
                        seeResultsButton

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
        }
        .navigationTitle("Assign Items")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private var unassignedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color.splitWarn)
            Text("\(session.unassignedFoodItemCount) item\(session.unassignedFoodItemCount == 1 ? "" : "s") not yet assigned")
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.splitWarn.opacity(0.12))
    }

    private var instructionCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color(red: 0.72, green: 0.46, blue: 1.0))
            Text("Tap each item to select who had it. Items can be shared between multiple people.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.72, green: 0.46, blue: 1.0).opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(red: 0.72, green: 0.46, blue: 1.0).opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func surchargesInfo(surcharges: [LineItem]) -> some View {
        let total = surcharges.reduce(Decimal(0)) { $0 + $1.amount }
        return GlassCard(padding: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tax, Tips & Fees")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Will be split on the results screen")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                CurrencyText(amount: total, font: .system(.subheadline, design: .rounded, weight: .semibold), color: Color.splitWarn)
            }
        }
    }

    private var emptyState: some View {
        GlassCard {
            VStack(spacing: 12) {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("No items found")
                    .font(.system(.body, design: .rounded, weight: .medium))
                Text("Go back and add items to the receipt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var seeResultsButton: some View {
        let blocked = session.splitMode == .itemized && session.unassignedFoodItemCount > 0
        return Button {
            session.navigateToResults()
        } label: {
            HStack {
                Text("See Results")
                Image(systemName: "arrow.right.circle.fill")
            }
            .font(.system(.body, design: .rounded, weight: .semibold))
            .foregroundStyle(blocked ? Color.secondary : Color.splitBg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                Capsule()
                    .fill(
                        blocked
                        ? AnyShapeStyle(Color.white.opacity(0.12))
                        : AnyShapeStyle(LinearGradient(
                            colors: [Color.splitTeal, Color.splitAccent],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(blocked)
        .padding(.top, 8)
    }
}
