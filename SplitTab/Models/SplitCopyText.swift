import Foundation

/// Readable plain text for individual messages and group chats.
enum SplitCopyText {
    static func cleanLabel(_ value: String) -> String {
        value.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func person(_ person: PersonResult, currency: String, breakdown: Bool) -> String {
        let money: (Decimal) -> String = { TripCurrency.formatDecimal($0, currency) }
        let name = cleanLabel(person.name)
        guard breakdown else { return "\(name)\nTotal: \(money(person.total))" }
        var lines = [name, ""]
        lines += person.assignedItems.map { "• \(cleanLabel($0.item.name)): \(money($0.shareAmount))" }
        if !person.assignedItems.isEmpty { lines.append("") }
        lines.append("Subtotal: \(money(person.itemSubtotal))")
        if person.feeShare != 0 { lines.append("Tax, tip & fees: \(money(person.feeShare))") }
        if person.discountShare != 0 { lines.append("Discounts: \(money(person.discountShare))") }
        let rounding = person.total - person.itemSubtotal - person.feeShare - person.discountShare
        if rounding != 0 { lines.append("Rounding adjustment: \(money(rounding))") }
        lines += ["", "Total: \(money(person.total))"]
        return lines.joined(separator: "\n")
    }

    static func everyone(_ result: SplitResult, currency: String, title: String?, breakdown: Bool) -> String {
        let name = title.map(cleanLabel)
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
        return "\(heading)\nBill total: \(TripCurrency.formatDecimal(total, currency))\n\n\(people)"
    }
}

#if canImport(UIKit)
import UIKit

/// Offer rich text without leaving Markdown punctuation in plain-text chat pastes.
@MainActor
enum ShareClipboard {
    static func copy(_ text: String) {
        let rich = NSMutableAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 16)])
        let lines = text.components(separatedBy: "\n")
        var offset = 0
        var htmlLines: [String] = []
        for (index, line) in lines.enumerated() {
            let isTotal = line.hasPrefix("Total:") || line.hasPrefix("Bill total:")
                || line.hasPrefix("Total to pay:") || line.hasPrefix("Total to repay:")
            let strong = index == 0 || isTotal
            if strong, !line.isEmpty {
                rich.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: 16), range: NSRange(location: offset, length: (line as NSString).length))
            }
            let escaped = line.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
            htmlLines.append(strong ? "<strong>\(escaped)</strong>" : escaped)
            offset += (line as NSString).length + 1
        }
        let html = "<html><head><meta charset=\"utf-8\"></head><body><div style=\"font-family: -apple-system, sans-serif; font-size: 16px; white-space: pre-wrap;\">\(htmlLines.joined(separator: "<br>"))</div></body></html>"
        var representations: [String: Any] = [
            "public.utf8-plain-text": text,
            "public.html": Data(html.utf8)
        ]
        if let rtf = try? rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            representations["public.rtf"] = rtf
        }
        UIPasteboard.general.setItems([representations])
    }
}
#endif
