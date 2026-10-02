import Foundation

/// Local development configuration. No API credential is bundled with the app.
enum ReceiptAPIConfiguration {
    static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    static var apiKey: String {
        ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
