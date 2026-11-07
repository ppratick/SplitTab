import Foundation
import CoreFoundation

struct ReceiptData: Equatable, Codable {
    var items: [LineItem]        // .item
    var surcharges: [LineItem]   // .tax, .tip, .fee
    var discounts: [LineItem]    // .discount
    var merchantName: String? = nil
    var parsedTotal: Decimal?    // printed total due, never a reconstructed total
    var currencyCode: String? = nil
    var printedTotals: [String: Decimal]? = nil
    var includedTax: Decimal? = nil
    var conversion: ReceiptConversion? = nil
    var original: ReceiptOriginal? = nil
    var archiveID: UUID? = nil

    var itemSubtotal: Decimal {
        items.reduce(0) { $0 + $1.amount }
    }

    var surchargeTotal: Decimal {
        surcharges.reduce(0) { $0 + $1.amount }
    }

    var discountTotal: Decimal {
        discounts.reduce(0) { $0 + $1.amount }
    }

    var grandTotal: Decimal {
        itemSubtotal + surchargeTotal + discountTotal
    }

    var totalDiscrepancy: Decimal? {
        guard let parsed = parsedTotal else { return nil }
        let diff = parsed - grandTotal
        let magnitude = diff < 0 ? -diff : diff
        return magnitude > Decimal(string: "0.01")! ? diff : nil
    }

    static var empty: ReceiptData {
        ReceiptData(items: [], surcharges: [], discounts: [], parsedTotal: nil)
    }
}

/// Original receipt prices remain authoritative when editing a converted receipt.
struct ReceiptOriginal: Equatable, Codable {
    var currency: String
    var items: [LineItem]
    var surcharges: [LineItem]
    var discounts: [LineItem]
    var parsedTotal: Decimal?
    var includedTax: Decimal?
}

struct ReceiptConversion: Equatable, Codable {
    var sourceCurrency: String
    var targetCurrency: String
    var rate: Decimal
    var sourceTotal: Decimal
    var rateLabel: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 6
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSDecimalNumber(decimal: rate)) ?? NSDecimalNumber(decimal: rate).stringValue
    }
}

extension ReceiptData {
    var editableReceipt: ReceiptData {
        guard let original else { return self }
        return ReceiptData(items: original.items, surcharges: original.surcharges, discounts: original.discounts, merchantName: merchantName, parsedTotal: original.parsedTotal, currencyCode: original.currency, printedTotals: printedTotals, includedTax: original.includedTax, archiveID: archiveID)
    }

    static func normalizedCurrency(_ value: String?) -> String? {
        guard let value else { return nil }
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if ["CG", "XCG", "ANG", "NAF", "NAƒ"].contains(code) { return "XCG" }
        if ["US$", "US", "USD"].contains(code) { return "USD" }
        return TripCurrency.codes.contains(code) ? code : nil
    }

    /// Remove informational tax only when it is explicitly included or reconciles
    /// with the printed amount due. Extra tips and fees remain payable.
    mutating func reconcileIncludedTax(explicitlyIncluded: Bool = false) {
        let taxes = surcharges.filter { $0.category == .tax }
        guard !taxes.isEmpty else { return }
        let tax = taxes.reduce(Decimal(0)) { $0 + $1.amount }
        let reconciles = parsedTotal.map { abs($0 - (grandTotal - tax)) <= Decimal(string: "0.01")! } ?? false
        guard explicitlyIncluded || reconciles else { return }
        includedTax = (includedTax ?? 0) + tax
        surcharges.removeAll { $0.category == .tax }
    }

    func inferredRate(to target: String) -> Decimal? {
        guard let source = currencyCode else { return nil }
        if source == target { return 1 }
        guard let from = printedTotals?[source], let to = printedTotals?[target], from > 0, to > 0 else { return nil }
        return to / from
    }

    /// Convert actual prices, with largest-remainder rounding across signed lines.
    /// Informational alternate totals are never charged as items.
    func converted(to target: String, rate suppliedRate: Decimal? = nil) throws -> ReceiptData {
        if original != nil {
            let rate = suppliedRate ?? (target == conversion?.targetCurrency ? conversion?.rate : nil)
            return try editableReceipt.converted(to: target, rate: rate)
        }
        guard let source = currencyCode, TripCurrency.codes.contains(target) else {
            throw TripIssue("Choose the currency printed on the receipt first.")
        }
        if source == target { return self }
        guard let rate = suppliedRate ?? inferredRate(to: target), !rate.isNaN, rate > 0, rate <= 1_000_000 else {
            throw TripIssue("Enter a rate for 1 \(source) in \(target). No conversion was printed on this receipt.")
        }
        let all = items + surcharges + discounts
        let factor = TripCurrency.factor(target)
        let exact = all.map { $0.amount * rate * factor }
        guard exact.allSatisfy({ !$0.isNaN && abs($0) <= 1_000_000_000 * factor }) else {
            throw TripIssue("The converted amounts are too large. Check the rate.")
        }
        var floors = exact.map { value -> Decimal in
            var value = value, rounded = Decimal()
            NSDecimalRound(&rounded, &value, 0, .down)
            return rounded
        }
        var targetMinor = grandTotal * rate * factor, roundedTotal = Decimal()
        NSDecimalRound(&roundedTotal, &targetMinor, 0, .plain)
        let remaining = NSDecimalNumber(decimal: roundedTotal - floors.reduce(0, +)).intValue
        guard remaining >= 0 && remaining <= all.count else { throw TripIssue("Could not reconcile converted receipt amounts.") }
        let ranked = all.indices.sorted {
            let left = exact[$0] - floors[$0], right = exact[$1] - floors[$1]
            return left == right ? $0 < $1 : left > right
        }
        for index in ranked.prefix(remaining) { floors[index] += 1 }
        let converted = all.indices.map { index -> LineItem in
            var line = all[index]
            line.amount = floors[index] / factor
            return line
        }
        guard zip(all, converted).allSatisfy({ original, updated in
            original.amount > 0 ? updated.amount > 0 : updated.amount <= 0
        }) else { throw TripIssue("An item rounds to zero in this currency. Use the receipt currency or a more precise currency.") }
        var result = self
        result.items = Array(converted.prefix(items.count))
        result.surcharges = Array(converted.dropFirst(items.count).prefix(surcharges.count))
        result.discounts = Array(converted.suffix(discounts.count))
        result.parsedTotal = parsedTotal.map { rounded($0 * rate, currency: target) }
        result.includedTax = includedTax.map { rounded($0 * rate, currency: target) }
        result.currencyCode = target
        result.conversion = ReceiptConversion(sourceCurrency: source, targetCurrency: target, rate: rate, sourceTotal: grandTotal)
        result.original = ReceiptOriginal(currency: source, items: items, surcharges: surcharges, discounts: discounts, parsedTotal: parsedTotal, includedTax: includedTax)
        return result
    }

    private func rounded(_ value: Decimal, currency: String) -> Decimal {
        var value = value, result = Decimal()
        NSDecimalRound(&result, &value, TripCurrency.digits(currency), .plain)
        return result
    }

    /// Shared, testable extraction mapping independent of image/network handling.
    static func extracted(from data: Data) throws -> ReceiptData {
        guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TripIssue("Could not read the receipt response.")
        }
        func number(_ value: Any?) -> Decimal? {
            if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() {
                return Decimal(string: value.stringValue, locale: Locale(identifier: "en_US_POSIX"))
            }
            if let value = value as? String { return try? TripCurrency.parse(value) }
            return nil
        }
        func lines(_ key: String, category: LineItemCategory) -> [LineItem] {
            (parsed[key] as? [[String: Any]] ?? []).compactMap { entry in
                guard let name = entry["name"] as? String, !name.isEmpty,
                      let price = number(entry["price"]), price > 0 else { return nil }
                return LineItem(name: name, amount: category == .discount ? -price : price, category: category)
            }
        }
        var receipt = ReceiptData(items: lines("items", category: .item), surcharges: lines("fees", category: .fee), discounts: lines("discounts", category: .discount), merchantName: parsed["merchant_name"] as? String, parsedTotal: number(parsed["total"]))
        receipt.currencyCode = normalizedCurrency(parsed["currency"] as? String)
        for (key, category) in [("tax", LineItemCategory.tax), ("tip", .tip)] {
            if let value = number(parsed[key]), value > 0 {
                receipt.surcharges.append(LineItem(name: key.capitalized, amount: value, category: category, sourcePercent: number(parsed[key + "_pct"])))
            }
        }
        var totals: [String: Decimal] = [:]
        if let code = receipt.currencyCode, let total = receipt.parsedTotal, total > 0 { totals[code] = total }
        for entry in parsed["alternate_totals"] as? [[String: Any]] ?? [] {
            if let code = normalizedCurrency(entry["currency"] as? String), let total = number(entry["total"]), total > 0, totals[code] == nil { totals[code] = total }
        }
        receipt.printedTotals = totals.isEmpty ? nil : totals
        receipt.reconcileIncludedTax(explicitlyIncluded: parsed["tax_included"] as? Bool == true)
        return receipt
    }
}
