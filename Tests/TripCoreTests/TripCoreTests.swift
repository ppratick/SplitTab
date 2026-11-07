import XCTest
import SwiftData
@testable import TripCore

final class TripCoreTests: XCTestCase {
    let me = TripParticipant(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Me")
    let alex = TripParticipant(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Alex")
    let sam = TripParticipant(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "Sam")
    func trip() -> TripRecord { TripRecord(name: "Weekend", participants: [me, alex, sam], me: me.id) }
    func expense(_ amount: Int64, payer: UUID? = nil, ids: [UUID]? = nil, mode: TripSplit = .equal, inputs: [UUID: Decimal] = [:]) throws -> TripExpense {
        var e = TripExpense(title: "Dinner", amount: amount, payer: payer ?? me.id, participants: ids ?? [me.id, alex.id, sam.id], mode: mode, inputs: inputs)
        e.shares = try TripMath.shares(e, currency: "USD")
        return e
    }
    func testDifferentPayersAndDirectSettlement() throws {
        var t = trip()
        t.save(try expense(12000)); t.save(try expense(6000, payer: alex.id))
        XCTAssertEqual(t.balances, [me.id: 6000, alex.id: 0, sam.id: -6000])
        XCTAssertEqual(TripMath.settlements(t), [
            TripTransfer(sender: alex.id, recipient: me.id, amount: 2000),
            TripTransfer(sender: sam.id, recipient: me.id, amount: 4000),
            TripTransfer(sender: sam.id, recipient: alex.id, amount: 2000)
        ])
        try TripMath.validate(t)
    }
    func assertSettles(_ input: TripRecord, file: StaticString = #filePath, line: UInt = #line) {
        var trip = input
        let transfers = TripMath.settlements(trip)
        for transfer in transfers {
            XCTAssertEqual(TripMath.settlementBreakdown(trip, transfer: transfer).reduce(0) { $0 + $1.amount }, transfer.amount, file: file, line: line)
            trip.save(TripPayment(sender: transfer.sender, recipient: transfer.recipient, amount: transfer.amount))
        }
        XCTAssertTrue(trip.settled, file: file, line: line)
        XCTAssertTrue(TripMath.settlements(trip).isEmpty, file: file, line: line)
    }
    func testCuracaoRepaysOriginalPayersWithMutualOffset() throws {
        let people = ["Pratick", "Biplop", "Matt", "Bill", "Andrew", "Ethan", "Stefan"].map { TripParticipant(name: $0) }
        let ids = people.map(\.id)
        var t = TripRecord(name: "Curaçao", participants: people, me: ids[0])
        t.save(try expense(84000, payer: ids[3], ids: ids))
        t.save(try expense(232750, payer: ids[2], ids: ids))
        t.save(try expense(283515, payer: ids[2], ids: [ids[0], ids[2], ids[4], ids[5], ids[6]]))
        let suggestions = TripMath.settlements(t)
        let matt = suggestions.filter { $0.recipient == ids[2] }
        let bill = suggestions.filter { $0.recipient == ids[3] }
        XCTAssertEqual(matt.reduce(0) { $0 + $1.amount }, 414312)
        XCTAssertEqual(bill.reduce(0) { $0 + $1.amount }, 60000)
        XCTAssertEqual(matt.first { $0.sender == ids[0] }?.amount, 89953)
        XCTAssertEqual(matt.first { $0.sender == ids[1] }?.amount, 33250)
        XCTAssertEqual(matt.first { $0.sender == ids[3] }?.amount, 21250)
        XCTAssertEqual(bill.count, 5)
        XCTAssertTrue(bill.allSatisfy { $0.amount == 12000 })
        assertSettles(t)
        // Previously suggested transfers remain valid; no data migration needed.
        for i in [0, 4, 5, 6] { t.save(TripPayment(sender: ids[i], recipient: ids[2], amount: 101953)) }
        t.save(TripPayment(sender: ids[1], recipient: ids[3], amount: 38750))
        t.save(TripPayment(sender: ids[1], recipient: ids[2], amount: 6500))
        XCTAssertTrue(t.settled)
        XCTAssertTrue(TripMath.settlements(t).isEmpty)
    }
    func testCircularDebtAndHistoricalIndirectPayment() throws {
        var t = trip()
        t.save(try expense(1000, payer: me.id, ids: [alex.id]))
        t.save(try expense(1000, payer: alex.id, ids: [sam.id]))
        t.save(try expense(1000, payer: sam.id, ids: [me.id]))
        XCTAssertTrue(TripMath.settlements(t).isEmpty)
        t = trip()
        t.save(try expense(12000)); t.save(try expense(6000, payer: alex.id))
        let payment = TripPayment(sender: sam.id, recipient: me.id, amount: 3000)
        t.save(payment)
        assertSettles(t)
        var correction = payment; correction.amount = 6000; correction.fx = nil; t.save(correction)
        XCTAssertTrue(TripMath.settlements(t).isEmpty)
        t.payments.removeAll()
        assertSettles(t)
    }
    func testRefundAfterExpenseDeletionAndMixedCurrencyCredit() throws {
        var t = trip()
        var e = try expense(12000)
        try e.convert(currency: "XCG", reporting: "USD", rate: Decimal(string: "0.5")!)
        t.save(e)
        var p = TripPayment(sender: sam.id, recipient: me.id, amount: 1000)
        p.fx = try TripFX.make(amount: p.amount, currency: "EUR", reporting: "USD", rate: 2)
        t.save(p)
        XCTAssertFalse(TripMath.settlements(t).contains { $0.sender == sam.id })
        assertSettles(t)
        e.amount = 18000; e.shares = try TripMath.shares(e, currency: "XCG")
        try e.convert(currency: "XCG", reporting: "USD", rate: Decimal(string: "0.5")!)
        t.save(e)
        XCTAssertEqual(TripMath.settlements(t).first { $0.sender == sam.id }?.amount, 1000)
        assertSettles(t)
        t.expenses.removeAll()
        XCTAssertEqual(TripMath.settlements(t), [TripTransfer(sender: me.id, recipient: sam.id, amount: 2000)])
        assertSettles(t)
    }
    func testSubsetAndPayerOutsideSubset() throws {
        var t = trip(); t.save(try expense(1001, payer: me.id, ids: [alex.id, sam.id]))
        XCTAssertEqual(t.balances, [me.id: 1001, alex.id: -501, sam.id: -500])
    }
    func testWeightedAndPercentageSplits() throws {
        let e = try expense(30000, mode: .weights, inputs: [me.id: 2, alex.id: 1, sam.id: 1])
        XCTAssertEqual(e.shares, [me.id: 15000, alex.id: 7500, sam.id: 7500])
        let p = try expense(30000, mode: .percentage, inputs: [me.id: 50, alex.id: 25, sam.id: 25])
        XCTAssertEqual(p.shares, e.shares)
    }
    func testExactAndInvalidTotals() throws {
        XCTAssertEqual(try expense(600, mode: .exact, inputs: [me.id: 1, alex.id: 2, sam.id: 3]).shares, [me.id: 100, alex.id: 200, sam.id: 300])
        XCTAssertThrowsError(try expense(601, mode: .exact, inputs: [me.id: 1, alex.id: 2, sam.id: 3]))
        XCTAssertThrowsError(try expense(600, mode: .exact, inputs: [me.id: -1, alex.id: 3, sam.id: 4]))
        XCTAssertThrowsError(try expense(600, mode: .percentage, inputs: [me.id: 33, alex.id: 33, sam.id: 33]))
        XCTAssertThrowsError(try expense(600, mode: .weights, inputs: [me.id: 0, alex.id: 1, sam.id: 1]))
        XCTAssertThrowsError(try expense(600, mode: .weights, inputs: [me.id: -2, alex.id: 1, sam.id: 1]))
        XCTAssertThrowsError(try expense(600, mode: .weights, inputs: [me.id: .nan, alex.id: 1, sam.id: 1]))
    }
    func testRoundingReconcilesIncludingTinyTotals() throws {
        for amount in Int64(1)...300 {
            for mode in [TripSplit.equal, .percentage, .weights] {
                let inputs: [UUID: Decimal] = mode == .percentage ? [me.id: 34, alex.id: 33, sam.id: 33] : [me.id: 2, alex.id: 1, sam.id: 1]
                let e = try expense(amount, mode: mode, inputs: inputs)
                XCTAssertEqual(e.shares.values.reduce(0, +), amount)
                XCTAssertTrue(e.shares.values.allSatisfy { $0 >= 0 })
                XCTAssertEqual(try TripMath.shares(e, currency: "USD"), e.shares)
            }
        }
        XCTAssertEqual(try expense(1).shares, [me.id: 1, alex.id: 0, sam.id: 0])
    }
    func itemized() -> TripExpense {
        let first = LineItem(name: "Shared", amount: 10, category: .item)
        let second = LineItem(name: "Sam's", amount: 20, category: .item)
        let r = ReceiptData(items: [first, second], surcharges: [LineItem(name: "Tax", amount: 3, category: .tax), LineItem(name: "Tip", amount: 6, category: .tip), LineItem(name: "Fee", amount: Decimal(string: "0.01")!, category: .fee)], discounts: [LineItem(name: "Discount", amount: -3, category: .discount)], parsedTotal: Decimal(string: "36.01")!)
        return TripExpense(title: "Receipt", amount: 3601, payer: me.id, participants: [me.id, alex.id, sam.id], mode: .itemized, receipt: r, assignments: [first.id: [me.id, alex.id], second.id: [sam.id]])
    }
    func testItemizedFeesDiscountsAndAssignments() throws {
        var e = itemized()
        XCTAssertEqual(try TripMath.shares(e, currency: "USD"), [me.id: 550, alex.id: 550, sam.id: 2501])
        e.fees = .even; e.discounts = .proportional
        XCTAssertEqual(try TripMath.shares(e, currency: "USD"), [me.id: 751, alex.id: 750, sam.id: 2100])
        e.assignments = [:]
        XCTAssertThrowsError(try TripMath.shares(e, currency: "USD"))
        e = itemized(); e.participants.removeLast()
        XCTAssertThrowsError(try TripMath.shares(e, currency: "USD"))
    }
    func testInvalidItemizedAndNegativeAllocation() throws {
        var e = itemized(); e.amount = 3600
        XCTAssertThrowsError(try TripMath.shares(e, currency: "USD"))
        e = itemized(); e.receipt!.discounts[0].amount = -29; e.amount = 1001
        XCTAssertThrowsError(try TripMath.shares(e, currency: "USD"))
        e.discounts = .proportional
        XCTAssertEqual(try TripMath.shares(e, currency: "USD").values.reduce(0, +), 1001)
    }
    func testPartialAndOtherParticipantPayments() throws {
        var t = trip(); t.save(try expense(12000))
        t.save(TripPayment(sender: sam.id, recipient: me.id, amount: 1500, note: "Zelle"))
        XCTAssertEqual(t.balances, [me.id: 6500, alex.id: -4000, sam.id: -2500])
        t.save(TripPayment(sender: alex.id, recipient: sam.id, amount: 1000))
        XCTAssertEqual(t.balances, [me.id: 6500, alex.id: -3000, sam.id: -3500])
        XCTAssertEqual(t.expenses.reduce(0) { $0 + $1.amount }, 12000)
    }
    func testExpenseEditAfterPaymentsAndIdempotentSave() throws {
        var t = trip(); var e = try expense(12000); t.save(e); t.save(e)
        let p = TripPayment(sender: sam.id, recipient: me.id, amount: 4000)
        t.save(p); t.save(p)
        let savedPayments = t.payments
        e.amount = 18000; e.shares = try TripMath.shares(e, currency: "USD"); t.save(e)
        XCTAssertEqual(t.expenses.count, 1); XCTAssertEqual(t.payments, savedPayments)
        XCTAssertEqual(t.balances, [me.id: 8000, alex.id: -6000, sam.id: -2000])
        t.expenses.removeAll()
        XCTAssertEqual(t.balances, [me.id: -4000, alex.id: 0, sam.id: 4000])
        t.payments.removeAll(); XCTAssertTrue(t.settled)
    }
    func testParticipantAdditionAndEnding() throws {
        var t = trip(); t.save(try expense(12000)); let e = t.expenses[0]
        t.participants.append(TripParticipant(name: "New person"))
        XCTAssertEqual(t.expenses[0], e); XCTAssertEqual(t.balances[t.participants.last!.id], 0)
        t.status = .ended; t.normalizeStatus(); XCTAssertEqual(t.status, .ended)
        for s in TripMath.settlements(t) { t.save(TripPayment(sender: s.sender, recipient: s.recipient, amount: s.amount)) }
        XCTAssertEqual(t.status, .archived)
        t.save(try expense(300)); XCTAssertEqual(t.status, .ended)
        t.status = .active; try TripMath.validate(t)
    }
    func testSettlementConservationAcrossManyBalances() throws {
        for n in 1...100 {
            var t = trip()
            t.save(try expense(Int64(n * 37), payer: alex.id))
            t.save(try expense(Int64(n * 19), payer: sam.id, ids: [me.id, sam.id]))
            t.save(TripPayment(sender: sam.id, recipient: alex.id, amount: Int64(n)))
            XCTAssertEqual(t.balances.values.reduce(0, +), 0)
            let suggestions = TripMath.settlements(t)
            XCTAssertEqual(suggestions, TripMath.settlements(t))
            for s in suggestions { XCTAssertGreaterThan(s.amount, 0); t.save(TripPayment(sender: s.sender, recipient: s.recipient, amount: s.amount)) }
            XCTAssertTrue(t.settled)
        }
    }
    func testGroupedAmountParsing() throws {
        XCTAssertEqual(try TripCurrency.parse("1,250.50"), Decimal(string: "1250.50"))
        XCTAssertEqual(try TripCurrency.parse("1,000,000"), 1000000)
        XCTAssertEqual(try TripCurrency.parse("0,560"), Decimal(string: "0.560"))
        XCTAssertEqual(try TripCurrency.parse("12,50"), Decimal(string: "12.50"))
        for invalid in ["12,34,567", "1,23.45", "1,234oops", "1.2.3"] {
            XCTAssertThrowsError(try TripCurrency.parse(invalid))
        }
    }
    func testSettlementCopyTotalsAndBreakdownForEveryoneAndOneSender() throws {
        var t = trip()
        t.save(try expense(12000)); t.save(try expense(6000, payer: alex.id))
        let before = t
        let all = TripMath.settlementText(t, breakdown: false)
        XCTAssertTrue(all.contains("Final payment: Alex → Me: USD 20.00"))
        XCTAssertTrue(all.contains("Final payment: Sam → Me: USD 40.00"))
        XCTAssertTrue(all.contains("Final payment: Sam → Alex: USD 20.00"))
        XCTAssertTrue(all.contains("Includes: Dinner"))
        XCTAssertFalse(all.contains("(Dinner, Dinner)"))
        let person = TripMath.settlementText(t, sender: sam.id, breakdown: false)
        XCTAssertTrue(person.contains("Total Sam sends: USD 60.00"))
        XCTAssertFalse(person.contains("Final payment: Alex → Me:"))
        XCTAssertTrue(TripMath.settlementText(t, sender: sam.id, breakdown: true).contains("Dinner: USD 40.00"))
        XCTAssertTrue(TripMath.settlementText(t, breakdown: true).contains("Subtract what Alex covered Me"))
        XCTAssertEqual(t, before)
    }
    func testCopiedTotalsNameOnlyTheRelevantExpensesAndDeduplicatePlaces() throws {
        var t = trip()
        for title in ["McDonalds", "Taxi", "Car Rental", "Taxi"] {
            var e = try expense(9000, payer: alex.id)
            e.title = title
            t.save(e)
        }
        var offset = try expense(3000)
        offset.title = "Lunch"
        t.save(offset)
        let text = TripMath.settlementText(t, sender: me.id, breakdown: false)
        XCTAssertTrue(text.contains("Final payment: Me → Alex: USD 110.00"), text)
        XCTAssertTrue(text.contains("Includes: McDonalds, Taxi, Car Rental, Lunch"), text)
        XCTAssertFalse(text.contains("McDonalds:"), text)
        let details = TripMath.settlementText(t, sender: me.id, breakdown: true)
        XCTAssertTrue(details.contains("McDonalds: USD 30.00"), details)
        XCTAssertTrue(details.contains("Subtract what Me covered Alex"), details)
    }

    func testCurrenciesAndStrictParsing() throws {
        XCTAssertEqual(try TripCurrency.minor(Decimal(string: "1.234")!, "KWD"), 1234)
        XCTAssertEqual(try TripCurrency.minor(12, "JPY"), 12)
        XCTAssertThrowsError(try TripCurrency.minor(Decimal(string: "1.001")!, "USD"))
        XCTAssertThrowsError(try TripCurrency.minor(.nan, "USD"))
        XCTAssertThrowsError(try TripCurrency.parse("12abc"))
        XCTAssertEqual(try TripCurrency.parse("12,50"), Decimal(string: "12.50"))
    }
    func testBackupRoundTripAndInvalidReferences() throws {
        var t = trip(); var e = itemized(); e.shares = try TripMath.shares(e, currency: t.currency)
        t.save(e); t.save(TripPayment(sender: sam.id, recipient: me.id, amount: 100, note: "Cash"))
        let data = try TripBackup.encode([t]); XCTAssertEqual(try TripBackup.decode(data), [t])
        var unsupported = TripBackup(trips: [t]); unsupported.version = 99
        XCTAssertThrowsError(try TripBackup.decode(JSONEncoder().encode(unsupported)))
        XCTAssertThrowsError(try TripBackup.decode(Data("garbage".utf8)))
        t.expenses[0].payer = UUID(); XCTAssertThrowsError(try TripBackup.encode([t]))
        t = trip(); t.save(try expense(300)); t.expenses[0].shares[me.id] = 99
        XCTAssertThrowsError(try TripBackup.encode([t]))
        t = trip(); t.participants.append(me); XCTAssertThrowsError(try TripBackup.encode([t]))
    }
    @MainActor func testTripDeletionPersistsAndPreservesOtherTrips() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Trips.store")
        func container() throws -> ModelContainer {
            try ModelContainer(for: SavedTrip.self, SavedActivity.self, configurations: ModelConfiguration("DeleteTest", url: url, cloudKitDatabase: .none))
        }
        var deleted = trip(); deleted.save(try expense(12000))
        deleted.save(TripPayment(sender: sam.id, recipient: me.id, amount: 1000))
        var retained = trip(); retained.id = UUID(); retained.name = "Keep this trip"
        try autoreleasepool {
            let store = try TripStore(container: container())
            try store.save(deleted); try store.save(retained)
            try store.delete(deleted.id)
            XCTAssertEqual(store.trips, [retained])
            XCTAssertEqual(try TripBackup.decode(store.export()), [retained])
        }
        try autoreleasepool {
            let store = try TripStore(container: container())
            XCTAssertEqual(store.trips, [retained])
            try store.delete(deleted.id) // Retrying a successful deletion is harmless.
            XCTAssertEqual(store.trips, [retained])
        }
    }
    @MainActor func testDurableStoreReopenAndRestoreAtomicity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Trips.store")
        func container() throws -> ModelContainer {
            try ModelContainer(for: SavedTrip.self, SavedActivity.self, configurations: ModelConfiguration("Test", url: url, cloudKitDatabase: .none))
        }
        var original = trip(); original.save(try expense(12000))
        original.save(TripPayment(sender: sam.id, recipient: me.id, amount: 1000))
        try autoreleasepool { let store = try TripStore(container: container()); try store.save(original); try store.save(original) }
        try autoreleasepool {
            let store = try TripStore(container: container())
            XCTAssertEqual(store.trips, [original])
            let backup = try store.export()
            XCTAssertThrowsError(try store.restore(Data("invalid".utf8)))
            XCTAssertEqual(store.trips, [original])
            var invalid = original; invalid.me = UUID()
            XCTAssertThrowsError(try store.save(invalid)); XCTAssertEqual(store.trips, [original])
            var other = trip(); other.id = UUID(); other.name = "Other"; try store.save(other)
            try store.restore(backup); XCTAssertEqual(store.trips, [original])
            try store.restore(backup); XCTAssertEqual(store.trips, [original])
        }
        try autoreleasepool { XCTAssertEqual(try TripStore(container: container()).trips, [original]) }
    }
}
