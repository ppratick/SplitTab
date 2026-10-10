import SwiftUI

struct SplitSetupView: View {
    var availablePeople: [Person]? = nil
    var expenseDetails: AnyView? = nil
    @Environment(SplitSessionViewModel.self) private var session
    @State private var appeared = false
    @State private var choosingEvenParticipants = false

    private var canContinue: Bool {
        !session.people.isEmpty && session.people.allSatisfy { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        ZStack {
            Color.splitBg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    if let expenseDetails { expenseDetails }
                    splitModeCard
                    if availablePeople == nil { peopleSection }
                    continueButton
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .keyboardDismissButton()
        .navigationTitle(availablePeople == nil ? "Who's Splitting?" : "Split Expense")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $choosingEvenParticipants) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 24) {
                        peopleSection
                        Button("Calculate") {
                            choosingEvenParticipants = false
                            session.navigateToResults()
                        }
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .foregroundStyle(.black.opacity(0.85))
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                        .background(Color.splitAccent, in: Capsule())
                        .disabled(!canContinue)
                        .opacity(canContinue ? 1 : 0.4)
                    }.padding(20)
                }
                .navigationTitle("Who's Splitting?")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { choosingEvenParticipants = false } } }
                .background(Color.splitBg.ignoresSafeArea())
            }.tint(Color.splitAccent).preferredColorScheme(.dark)
        }
        .onAppear {
            if session.people.isEmpty && availablePeople == nil {
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
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))

            SplitMethodCards(selection: session.splitMode) {
                session.splitMode = $0
                if $0 == .itemized, let availablePeople { session.people = availablePeople }
            }
        }
    }

    // MARK: - People

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Text("People")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("\(session.people.count)")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                Spacer()
                if availablePeople == nil { addPersonButton }
            }

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    if let availablePeople {
                        ForEach(availablePeople) { person in
                            Toggle(person.name, isOn: Binding(get: { session.people.contains { $0.id == person.id } }, set: { selected in
                                if selected { session.people.append(person) }
                                else { session.removePerson(id: person.id) }
                                session.people = availablePeople.filter { candidate in session.people.contains { $0.id == candidate.id } }
                            }))
                            .padding(.horizontal, 18).padding(.vertical, 12)
                        }
                    } else {
                    ForEach(Array(session.people.enumerated()), id: \.element.id) { idx, person in
                        PersonRowView(
                            person: person,
                            autoFocus: idx == 0,
                            onNameChange: { session.updatePersonName(person.id, name: $0) },
                            onDelete: { withAnimation { session.removePerson(id: person.id) } }
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        if idx < session.people.count - 1 {
                            Divider().overlay(Color.white.opacity(0.05)).padding(.leading, 70)
                        }
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
                Text("Add")
            }
            .font(.system(.caption, design: .rounded, weight: .bold))
            .foregroundStyle(session.people.count < 8 ? Color.splitAccent : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(session.people.count < 8 ? Color.splitAccent.opacity(0.1) : Color.white.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
        .disabled(session.people.count >= 8)
    }

    // MARK: - Continue Button

    private var continueButton: some View {
        Button {
            if session.splitMode == .even {
                if availablePeople != nil { choosingEvenParticipants = true }
                else { session.navigateToResults() }
            } else {
                if let availablePeople { session.people = availablePeople }
                session.navigate(to: .itemAssignment)
            }
        } label: {
            HStack(spacing: 8) {
                Text(session.splitMode == .even ? "Calculate" : "Assign Items")
                Image(systemName: session.splitMode == .even ? "equal.circle.fill" : "arrow.right")
                    .font(.system(size: 14, weight: .bold))
            }
            .font(.system(.body, design: .rounded, weight: .bold))
            .foregroundStyle((availablePeople != nil || canContinue) ? .black.opacity(0.85) : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                Capsule()
                    .fill((availablePeople != nil || canContinue) ? Color.splitAccent : Color.white.opacity(0.06))
                    .shadow(color: canContinue ? Color.splitAccent.opacity(0.25) : .clear, radius: 12, y: 4)
            )
        }
        .buttonStyle(.plain)
        .disabled(availablePeople == nil && !canContinue)
        .padding(.top, 4)
    }
}
