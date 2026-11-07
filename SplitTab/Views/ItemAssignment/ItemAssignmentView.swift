import SwiftUI

struct ItemAssignmentView: View {
    var availablePeople: [Person]? = nil
    @Environment(SplitSessionViewModel.self) private var session

    private var items: [LineItem] { session.receipt?.items ?? [] }

    var body: some View {
        ZStack {
            Color.splitBg.ignoresSafeArea()

            VStack(spacing: 0) {
                if session.unassignedItemCount > 0 {
                    unassignedBanner
                }

                ScrollView {
                    VStack(spacing: 16) {

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
                                            onToggleEveryone: {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                    session.toggleEveryone(itemId: item.id)
                                                }
                                            },
                                            onDelete: {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                    session.deleteLineItem(item)
                                                }
                                            }
                                        )

                                        if idx < items.count - 1 {
                                            Divider().overlay(Color.white.opacity(0.05))
                                        }
                                    }
                                }
                            }
                        } else {
                            emptyState
                        }

                        if let surcharges = session.receipt?.surcharges, !surcharges.isEmpty {
                            surchargesInfo(surcharges: surcharges)
                        }

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
        .onAppear {
            if let availablePeople { session.people = availablePeople }
        }
    }

    // MARK: - Subviews

    private var unassignedBanner: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.splitWarn)
                .frame(width: 8, height: 8)
            Text("\(session.unassignedItemCount) item\(session.unassignedItemCount == 1 ? "" : "s") not yet assigned")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.splitWarn.opacity(0.08))
    }

    private func surchargesInfo(surcharges: [LineItem]) -> some View {
        let total = surcharges.reduce(Decimal(0)) { $0 + $1.amount }
        return HStack(spacing: 12) {
            Image(systemName: "percent")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.splitWarn.opacity(0.7))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.splitWarn.opacity(0.1)))

            VStack(alignment: .leading, spacing: 2) {
                Text("Tax, Tips & Fees")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Will be split on the results screen")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            CurrencyText(amount: total, font: .system(.subheadline, design: .rounded, weight: .bold), color: Color.splitWarn)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var emptyState: some View {
        GlassCard {
            VStack(spacing: 14) {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.white.opacity(0.3))
                Text("No items found")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                Text("Go back and add items to the receipt.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var seeResultsButton: some View {
        let blocked = session.splitMode == .itemized && session.unassignedItemCount > 0
        return Button {
            if let availablePeople {
                let assignedIDs = items.reduce(into: Set<UUID>()) { ids, item in
                    ids.formUnion(session.assignments[item.id] ?? [])
                }
                session.people = availablePeople.filter { assignedIDs.contains($0.id) }
            }
            session.navigateToResults()
        } label: {
            HStack(spacing: 8) {
                Text("See Results")
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 16))
            }
            .font(.system(.body, design: .rounded, weight: .bold))
            .foregroundStyle(blocked ? Color.secondary : .black.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                Capsule()
                    .fill(blocked ? Color.white.opacity(0.06) : Color.splitAccent)
                    .shadow(color: blocked ? .clear : Color.splitAccent.opacity(0.25), radius: 12, y: 4)
            )
        }
        .buttonStyle(.plain)
        .disabled(blocked)
        .padding(.top, 4)
    }
}
