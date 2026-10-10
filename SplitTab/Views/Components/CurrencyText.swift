import SwiftUI

struct CurrencyText: View {
    @Environment(\.tripCurrencyCode) private var tripCurrencyCode
    let amount: Decimal
    var font: Font = .body
    var color: Color = .primary
    var showSign: Bool = false

    var body: some View {
        Text(formatted)
            .font(font)
            .foregroundStyle(color)
            .monospacedDigit()
    }

    private var formatted: String {
        if let code = tripCurrencyCode {
            return (showSign && amount > 0 ? "+" : "") + TripCurrency.formatDecimal(amount, code)
        }
        if showSign && amount > 0 {
            return "+" + amount.currencyString
        }
        return amount.currencyString
    }
}
