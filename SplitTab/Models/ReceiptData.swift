import Foundation

struct ReceiptData: Equatable {
    var items: [LineItem]        // .item
    var surcharges: [LineItem]   // .tax, .tip, .fee
    var discounts: [LineItem]    // .discount
    var parsedTotal: Decimal?    // raw total from OCR

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
