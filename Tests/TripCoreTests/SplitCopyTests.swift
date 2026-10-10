import XCTest
@testable import TripCore

final class SplitCopyTests: XCTestCase {
    func testFourCopyFormatsIncludeNamesCurrenciesAndReconciledTotals() throws {
        let a = Person(name: "Alex", colorIndex: 0)
        let b = Person(name: "Sam", colorIndex: 1)
        let item = LineItem(name: "Dinner", amount: 20, category: .item)
        let receipt = ReceiptData(items: [item], surcharges: [LineItem(name: "Tip", amount: 4, category: .tip)], discounts: [LineItem(name: "Coupon", amount: -2, category: .discount)], merchantName: "Beach Cafe", parsedTotal: nil)
        let result = try SplitCalculator.calculate(receipt: receipt, people: [a,b], mode: .itemized, assignments: [item.id: Set([a.id,b.id])], feeDistribution: .even)
        let person = result.personResults[0]
        XCTAssertEqual(SplitCopyText.person(person, currency: "USD", breakdown: false), "Alex\nTotal: USD 11.00")
        let details = SplitCopyText.person(person, currency: "USD", breakdown: true)
        for expected in ["Alex", "Dinner: USD 10.00", "Tax, tip & fees: USD 2.00", "Discounts: USD -1.00", "Total: USD 11.00"] { XCTAssertTrue(details.contains(expected), details) }
        let totals = SplitCopyText.everyone(result, currency: "USD", title: receipt.merchantName, breakdown: false)
        XCTAssertTrue(totals.contains("Beach Cafe")); XCTAssertTrue(totals.contains("Sam: USD 11.00"))
        XCTAssertTrue(totals.contains("Bill total: USD 22.00")); XCTAssertFalse(totals.contains("Subtotal"))
        let all = SplitCopyText.everyone(result, currency: "USD", title: nil, breakdown: true)
        XCTAssertTrue(all.contains("SplitTab bill")); XCTAssertEqual(all.components(separatedBy: "Subtotal:").count, 3)
    }
    func testRoundingIsExplainedAndPrecisionPreserved() {
        let person = PersonResult(id: UUID(), name: "Me", avatarColorIndex: 0, assignedItems: [], itemSubtotal: Decimal(string: "0.002")!, feeShare: 0, discountShare: 0, total: Decimal(string: "0.001")!)
        let text = SplitCopyText.person(person, currency: "KWD", breakdown: true)
        XCTAssertTrue(text.contains("Rounding adjustment: KWD -0.001"))
        XCTAssertTrue(text.contains("Total: KWD 0.001"))
    }
    func testMerchantNameRoundTripAndOlderReceipt() throws {
        var receipt = ReceiptData.empty
        receipt.merchantName = "Beach Cafe"
        XCTAssertEqual(try JSONDecoder().decode(ReceiptData.self, from: JSONEncoder().encode(receipt)), receipt)
        let old = Data(#"{"items":[],"surcharges":[],"discounts":[]}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(ReceiptData.self, from: old).merchantName)
    }
}
