import Foundation

struct ReceiptParser {

    // MARK: - Public Entry Point

    static func parse(lines: [String]) -> ReceiptData {
        var items: [LineItem] = []
        var surcharges: [LineItem] = []
        var discounts: [LineItem] = []
        var parsedTotal: Decimal?

        let processed = preprocess(lines)
        var i = 0

        while i < processed.count {
            let line = processed[i]
            let lookahead = processed.indices.contains(i + 1) ? processed[i + 1] : nil
            let (name, amount) = extractNameAndAmount(from: line, lookahead: lookahead)

            guard let amount, amount != 0 else { i += 1; continue }
            let category = classify(name: name, amount: amount)

            switch category {
            case .item:
                let isLow = amount > 200 || name.count < 2
                items.append(LineItem(name: name.isEmpty ? line : name, amount: amount,
                                      category: .item, isLowConfidence: isLow))
            case .tax:
                surcharges.append(LineItem(name: name, amount: amount, category: .tax))
            case .tip:
                surcharges.append(LineItem(name: name, amount: amount, category: .tip))
            case .fee:
                surcharges.append(LineItem(name: name, amount: amount, category: .fee))
            case .discount:
                let neg = amount < 0 ? amount : -amount
                discounts.append(LineItem(name: name, amount: neg, category: .discount))
            case .unknown:
                let lc = name.lowercased()
                if totalKeywords.contains(where: { lc.contains($0) }) {
                    if let existing = parsedTotal {
                        parsedTotal = max(existing, amount)
                    } else {
                        parsedTotal = amount
                    }
                }
                // subtotals are suppressed
            }
            i += 1
        }

        return ReceiptData(items: items, surcharges: surcharges, discounts: discounts, parsedTotal: parsedTotal)
    }

    // MARK: - Private

    private static let priceRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\$?\s*(\d{1,4})[,.](\d{2})\b"#)
    }()

    private static let taxKeywords      = ["tax", "hst", "gst", "vat", "sales tax", "state tax", "local tax"]
    private static let tipKeywords      = ["tip", "gratuity", "service charge", "svc"]
    private static let feeKeywords      = ["fee", "surcharge", "delivery", "convenience", "charge"]
    private static let discountKeywords = ["discount", "coupon", "promo", "savings", " off", "comp"]
    private static let subtotalKeywords = ["subtotal", "sub total", "sub-total", "food total", "item total", "net total", "pre-tax"]
    private static let totalKeywords    = ["total", "amount due", "balance due", "grand total", "please pay", "amount tendered"]
    private static let suppressKeywords = ["payment", "cash", "visa", "mastercard", "amex", "discover", "debit", "credit",
                                           "change", "amount paid", "balance", "check", "cheque", "card", "cash back",
                                           "approved", "auth", "transaction", "order #", "table", "server", "guest",
                                           "terminal", "ref #", "invoice", "receipt #"]

    private static func preprocess(_ lines: [String]) -> [String] {
        lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.count > 1 }
    }

    private static func extractNameAndAmount(from line: String, lookahead: String?) -> (name: String, amount: Decimal?) {
        let range = NSRange(line.startIndex..., in: line)
        let matches = priceRegex.matches(in: line, range: range)

        if let match = matches.last {
            let matchRange = Range(match.range, in: line)!
            let rawName = String(line[line.startIndex ..< matchRange.lowerBound])
                .trimmingCharacters(in: CharacterSet(charactersIn: " .:$"))
            let dollars = (Range(match.range(at: 1), in: line)).flatMap { Decimal(string: String(line[$0])) } ?? 0
            let cents   = (Range(match.range(at: 2), in: line)).flatMap { Decimal(string: String(line[$0])) } ?? 0
            let amount  = dollars + cents / 100
            // Strip any residual embedded prices from the name (e.g. "Burger 8.99 8.99" → "Burger")
            let cleanedName = stripEmbeddedPrices(from: rawName)
            let finalName = cleanedName.isEmpty ? (rawName.isEmpty ? line : rawName) : cleanedName
            return (finalName, amount)
        }

        return (line, nil)
    }

    private static func classify(name: String, amount: Decimal) -> LineItemCategory {
        let lc = name.lowercased()
        if amount < 0 || discountKeywords.contains(where: { lc.contains($0) }) { return .discount }
        if taxKeywords.contains(where: { lc.contains($0) })      { return .tax }
        if tipKeywords.contains(where: { lc.contains($0) })      { return .tip }
        if feeKeywords.contains(where: { lc.contains($0) })      { return .fee }
        if subtotalKeywords.contains(where: { lc.contains($0) }) { return .unknown }
        if totalKeywords.contains(where: { lc.contains($0) })    { return .unknown }
        if suppressKeywords.contains(where: { lc.contains($0) }) { return .unknown }
        return .item
    }

    // Strip any price patterns embedded in the name (e.g. "Burger 8.99" → "Burger")
    private static func stripEmbeddedPrices(from name: String) -> String {
        let range = NSRange(name.startIndex..., in: name)
        let cleaned = priceRegex.stringByReplacingMatches(in: name, range: range, withTemplate: "")
        return cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " .:$@x×*"))
    }
}
