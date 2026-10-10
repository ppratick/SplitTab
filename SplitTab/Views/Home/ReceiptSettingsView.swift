import SwiftUI

struct ReceiptSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var hasSavedKey = false
    @State private var error: String?
    @State private var confirmingRemoval = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.splitBg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Receipt scanning")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 20) {
                            Label(hasSavedKey ? "Key saved on this device" : "No saved key", systemImage: hasSavedKey ? "checkmark.shield" : "key")
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("settings.keyStatus")
                            SecureField(hasSavedKey ? "Paste replacement API key" : "Paste OpenAI API key", text: $key)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .accessibilityIdentifier("settings.apiKey")
                                .onSubmit {
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                }
                            Button(hasSavedKey ? "Replace Key" : "Save Key") {
                                perform {
                                    try ReceiptAPIConfiguration.saveKey(key)
                                    key = ""
                                    hasSavedKey = true
                                }
                            }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if hasSavedKey {
                                Button("Remove Key", role: .destructive) { confirmingRemoval = true }
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.splitCard, in: RoundedRectangle(cornerRadius: 20))
                    }.padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .keyboardDismissButton()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear {
                perform { hasSavedKey = try ReceiptAPIConfiguration.savedKey() != nil }
            }
            .onDisappear { key = "" }
            .confirmationDialog("Remove the saved API key?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
                Button("Remove Key", role: .destructive) {
                    perform {
                        try ReceiptAPIConfiguration.removeKey()
                        hasSavedKey = false
                        key = ""
                    }
                }
            }
            .alert("Couldn’t update receipt settings", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
        .tint(Color.splitAccent)
        .preferredColorScheme(.dark)
        .presentationBackground(Color.splitBg)
    }

    private func perform(_ operation: () throws -> Void) {
        do { try operation() } catch { self.error = error.localizedDescription }
    }
}
