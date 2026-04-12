import SwiftUI

struct SplitSetupView: View {
    @Environment(SplitSessionViewModel.self) private var session
    @State private var appeared = false

    private var canContinue: Bool {
        !session.people.isEmpty && session.people.allSatisfy { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        ZStack {
            Color.splitBg.ignoresSafeArea()
            LinearGradient(
                colors: [Color.splitAccent.opacity(0.07), Color.clear],
                startPoint: .top, endPoint: .center
            ).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {

                    // Split mode picker
                    splitModeCard

                    // People section
                    peopleSection

                    // Continue button
                    continueButton

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Who's Splitting?")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear {
            if session.people.isEmpty {
                session.addPerson()
                session.addPerson()
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { appeared = true }
        }
    }

    // MARK: - Split Mode

    private var splitModeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How do you want to split?")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ForEach(SplitMode.allCases) { mode in
                    splitModeChip(mode)
                }
            }
        }
    }

    private func splitModeChip(_ mode: SplitMode) -> some View {
        let selected = session.splitMode == mode

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                session.splitMode = mode
            }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(selected ? Color.splitBg : Color.splitTeal)

                Text(mode.rawValue)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(selected ? Color.splitBg : .primary)

                Text(mode.description)
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.splitBg.opacity(0.7) : .secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(selected
                          ? AnyShapeStyle(LinearGradient(colors: [Color.splitTeal, Color.splitAccent], startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(.regularMaterial))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(selected ? Color.clear : Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - People

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("People (\(session.people.count))")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                addPersonButton
            }

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(session.people.enumerated()), id: \.element.id) { idx, person in
                        PersonRowView(
                            person: person,
                            autoFocus: idx == 0,
                            onNameChange: { session.updatePersonName(person.id, name: $0) },
                            onDelete: { withAnimation { session.removePerson(id: person.id) } }
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        if idx < session.people.count - 1 {
                            Divider().overlay(Color.white.opacity(0.07)).padding(.leading, 70)
                        }
                    }
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: session.people.count)
        }
    }

    private var addPersonButton: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                session.addPerson()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                Text("Add Person")
            }
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(session.people.count < 8 ? Color.splitTeal : Color.secondary)
        }
        .buttonStyle(.plain)
        .disabled(session.people.count >= 8)
    }

    // MARK: - Continue Button

    private var continueButton: some View {
        Button {
            if session.splitMode == .even {
                session.navigateToResults()
            } else {
                session.navigate(to: .itemAssignment)
            }
        } label: {
            HStack {
                Text(session.splitMode == .even ? "Calculate" : "Assign Items")
                Image(systemName: session.splitMode == .even ? "equal.circle.fill" : "arrow.right")
            }
            .font(.system(.body, design: .rounded, weight: .semibold))
            .foregroundStyle(canContinue ? Color.splitBg : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                Capsule()
                    .fill(
                        canContinue
                        ? AnyShapeStyle(LinearGradient(colors: [Color.splitTeal, Color.splitAccent], startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(Color.white.opacity(0.1))
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!canContinue)
        .padding(.top, 8)
    }
}
