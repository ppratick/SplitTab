import SwiftUI

struct PersonRowView: View {
    let person: Person
    var autoFocus: Bool = false
    var onNameChange: (String) -> Void
    var onDelete: () -> Void

    @State private var name: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 14) {
            PersonAvatar(person: person, size: 40)

            TextField("Name", text: $name)
                .font(.system(.body, design: .rounded))
                .focused($isFocused)
                .onSubmit { onNameChange(name) }
                .onChange(of: name) { _, newValue in
                    onNameChange(newValue)
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused { onNameChange(name) }
                }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .onAppear {
            name = person.name
            if person.name.isEmpty && autoFocus { isFocused = true }
        }
    }
}
