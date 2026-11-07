import Foundation

/// Readable plain text for individual messages and group chats.
enum SplitCopyText {
    static func cleanLabel(_ value: String) -> String {
        value.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func bold(_ value: String) -> String { "*" + cleanLabel(value).replacingOccurrences(of: "*", with: "") + "*" }

    static func person(_ person: PersonResult, currency: String, breakdown: Bool) -> String {
        let money: (Decimal) -> String = { TripCurrency.formatDecimal($0, currency) }
        let name = cleanLabel(person.name)
        guard breakdown else { return "\(bold(name))\n\(bold("Total: " + money(person.total)))" }
        var lines = [bold(name), ""]
        lines += person.assignedItems.map { "• \(cleanLabel($0.item.name)): \(money($0.shareAmount))" }
        if !person.assignedItems.isEmpty { lines.append("") }
        lines.append("Subtotal: \(money(person.itemSubtotal))")
        if person.feeShare != 0 { lines.append("Tax, tip & fees: \(money(person.feeShare))") }
        if person.discountShare != 0 { lines.append("Discounts: \(money(person.discountShare))") }
        let rounding = person.total - person.itemSubtotal - person.feeShare - person.discountShare
        if rounding != 0 { lines.append("Rounding adjustment: \(money(rounding))") }
        lines += ["", bold("Total: " + money(person.total))]
        return lines.joined(separator: "\n")
    }

    static func everyone(_ result: SplitResult, currency: String, title: String?, breakdown: Bool) -> String {
        let name = title.map { cleanLabel($0) }
        let heading = name.flatMap { $0.isEmpty ? nil : $0 } ?? "SplitTab bill"
        let total = result.personResults.reduce(Decimal(0)) { $0 + $1.total }
        let people: String
        if breakdown {
            people = result.personResults.map { person($0, currency: currency, breakdown: true) }
                .joined(separator: "\n\n")
        } else {
            people = result.personResults.map {
                "• \(cleanLabel($0.name)): \(TripCurrency.formatDecimal($0.total, currency))"
            }.joined(separator: "\n")
        }
        return "\(bold(heading))\n\(bold("Bill total: " + TripCurrency.formatDecimal(total, currency)))\n\n\(people)"
    }
}

#if canImport(UIKit)
import UIKit

/// WhatsApp-compatible plain text. Bold markers survive chat clipboard pastes.
@MainActor
enum ShareClipboard {
    static func copy(_ text: String) throws {
        guard let store = TripStore.current else { throw TripIssue("History storage unavailable. Reopen the app before copying.") }
        try store.append(ActivityRecord(kind: "message.copied", title: "Copied shares / repayments", after: Data(text.utf8)))
        UIPasteboard.general.string = text
    }
}
#endif
