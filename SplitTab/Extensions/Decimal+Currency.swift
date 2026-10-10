import Foundation

extension Decimal {
    func currencyDigits(_ code: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = TripCurrency.digits(code)
        f.maximumFractionDigits = TripCurrency.digits(code)
        return f.string(from: NSDecimalNumber(decimal: self)) ?? "0"
    }

    func currencyString(code: String?) -> String {
        guard let code else { return currencyString }
        return TripCurrency.formatDecimal(self, code)
    }
    static func roundCurrency(_ value: Decimal, code: String?) -> Decimal {
        var input = value, result = Decimal()
        NSDecimalRound(&result, &input, code.map { TripCurrency.digits($0) } ?? 2, .plain)
        return result
    }

    /// Formatted as currency with the locale symbol directly adjacent, e.g. "$12.34"
    var currencyString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: self as NSDecimalNumber) ?? "$0.00"
    }

    /// Digits-only string (no symbol), always 2 decimal places, e.g. "104.88"
    var digitsString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: self as NSDecimalNumber) ?? "0.00"
    }

    static func roundToTwo(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 2, .plain)
        return result
    }
}
