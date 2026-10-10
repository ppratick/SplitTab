import XCTest
import SwiftData
@testable import TripCore

final class CurrencyTests: XCTestCase {
    let a = TripParticipant(name: "Me"), b = TripParticipant(name: "Alex"), c = TripParticipant(name: "Sam")
    func trip() -> TripRecord { TripRecord(name: "Curaçao", participants: [a, b, c], me: a.id) }
    func expense(_ amount: Int64, currency: String, rate: Decimal, payer: UUID? = nil) throws -> TripExpense {
        var e = TripExpense(title: "Dinner", amount: amount, payer: payer ?? a.id, participants: [a.id, b.id, c.id])
        e.shares = try TripMath.shares(e, currency: currency)
        try e.convert(currency: currency, reporting: "USD", rate: rate)
        return e
    }
    func testMixedExpensesPaymentsAndSavedRateStability() throws {
        var t = trip()
        let original = try expense(17900, currency: "XCG", rate: Decimal(string: "0.56")!)
        t.save(original)
        t.save(try expense(6000, currency: "USD", rate: 1, payer: b.id))
        XCTAssertEqual(t.expenses[0].amount, 17900)
        XCTAssertEqual(t.expenses[0].balanceAmount, 10024)
        XCTAssertEqual(t.balances.values.reduce(0, +), 0)
        let before = t.balances
        var payment = TripPayment(sender: c.id, recipient: b.id, amount: 1000)
        payment.fx = try TripFX.make(amount: payment.amount, currency: "EUR", reporting: "USD", rate: Decimal(string: "1.10")!)
        t.save(payment)
        XCTAssertEqual(t.balances[c.id], before[c.id]! + 1100)
        XCTAssertEqual(t.balances[b.id], before[b.id]! - 1100)
        XCTAssertEqual(t.expenses.reduce(0) { $0 + $1.balanceAmount }, 16024)
        // A subsequent expense uses a different rate; the prior allocation is unchanged.
        t.save(try expense(17900, currency: "XCG", rate: Decimal(string: "0.57")!))
        XCTAssertEqual(t.expenses[0], original)
        let restored = try TripBackup.decode(TripBackup.encode([t]))[0]
        XCTAssertEqual(restored, t)
        XCTAssertTrue(TripMath.summary(t).contains("1 XCG = 0.56 USD"))
        XCTAssertTrue(TripMath.summary(t).contains("EUR 10.00"))
        try TripMath.validate(t)
        for s in TripMath.settlements(t) { t.save(TripPayment(sender: s.sender, recipient: s.recipient, amount: s.amount)) }
        XCTAssertTrue(t.settled)
    }
    func testConversionPrecisionAndRemainders() throws {
        XCTAssertEqual(try TripFX.make(amount: 1234, currency: "KWD", reporting: "JPY", rate: 500).convertedAmount, 617)
        XCTAssertEqual(try TripFX.make(amount: 1, currency: "JPY", reporting: "KWD", rate: Decimal(string: "0.0025")!).convertedAmount, 3)
        for n in Int64(2)...300 {
            let e = try expense(n, currency: "XCG", rate: Decimal(string: "0.5586592179")!)
            XCTAssertEqual(e.shares.values.reduce(0, +), n)
            XCTAssertEqual(e.balanceShares.values.reduce(0, +), e.balanceAmount)
            XCTAssertTrue(e.balanceShares.values.allSatisfy { $0 >= 0 })
        }
    }
    func testRejectBadRatesAndConvertedSnapshots() throws {
        for rate: Decimal in [0, -1, .nan, 1_000_001] {
            XCTAssertThrowsError(try TripFX.make(amount: 100, currency: "XCG", reporting: "USD", rate: rate))
        }
        XCTAssertThrowsError(try TripFX.make(amount: 100, currency: "USD", reporting: "USD", rate: 2))
        XCTAssertThrowsError(try TripFX.make(amount: 1, currency: "USD", reporting: "JPY", rate: Decimal(string: "0.001")!))
        var t = trip(); t.save(try expense(100, currency: "XCG", rate: 1))
        t.expenses[0].fx!.convertedAmount += 1
        XCTAssertThrowsError(try TripMath.validate(t))
        t = trip(); t.save(try expense(100, currency: "XCG", rate: 1)); t.expenses[0].fx = nil
        XCTAssertThrowsError(try TripBackup.encode([t]))
    }
    func testOriginalItemizedSplitsArePreserved() throws {
        let item = LineItem(name: "Lunch", amount: Decimal(string: "10.01")!, category: .item)
        var e = TripExpense(title: "Lunch", amount: 1001, payer: a.id, participants: [a.id, b.id, c.id], mode: .itemized, receipt: ReceiptData(items: [item], surcharges: [], discounts: [], parsedTotal: nil), assignments: [item.id: [a.id, b.id, c.id]])
        e.shares = try TripMath.shares(e, currency: "XCG")
        let shares = e.shares
        try e.convert(currency: "XCG", reporting: "USD", rate: Decimal(string: "0.56")!)
        XCTAssertEqual(e.receipt!.items[0].amount, Decimal(string: "10.01"))
        XCTAssertEqual(e.shares, shares)
        XCTAssertEqual(e.balanceShares.values.reduce(0, +), 561)
    }
    func legacyData(_ trip: TripRecord) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(trip)) as! [String: Any]
        object.removeValue(forKey: "schemaVersion"); object.removeValue(forKey: "reportingCurrencyLocked")
        for field in ["expenses", "payments"] {
            object[field] = (object[field] as! [[String: Any]]).map { value in
                var v = value; v.removeValue(forKey: "fx"); v.removeValue(forKey: "reportingShares"); return v
            }
        }
        return try JSONSerialization.data(withJSONObject: object)
    }
    func testLegacyBackupMigrationKeepsPriorCurrencyAndAdvancedModes() throws {
        var t = trip(); t.currency = "KWD"
        var e = TripExpense(title: "Hotel", amount: 6000, payer: a.id, participants: [a.id, b.id], mode: .exact, inputs: [a.id: 2, b.id: 4])
        e.shares = try TripMath.shares(e, currency: "KWD"); t.save(e)
        t.save(TripPayment(sender: b.id, recipient: a.id, amount: 1000))
        let legacy = try legacyData(t)
        let raw = try JSONDecoder().decode(TripRecord.self, from: legacy)
        XCTAssertNil(raw.schemaVersion)
        let migrated = try raw.migrated()
        XCTAssertEqual(migrated.balances, t.balances)
        XCTAssertEqual(migrated.expenses[0].fx?.currency, "KWD")
        XCTAssertEqual(migrated.expenses[0].fx?.rate, 1)
        XCTAssertEqual(migrated.expenses[0].amount, 6000)
        XCTAssertEqual(migrated.expenses[0].mode, .exact)
        XCTAssertEqual(migrated.payments[0].fx?.convertedAmount, 1000)
        let envelope: [String: Any] = ["format": "SplitTab.Trips", "version": 1, "exportedAt": 0, "trips": [try JSONSerialization.jsonObject(with: legacy)]]
        XCTAssertEqual(try TripBackup.decode(JSONSerialization.data(withJSONObject: envelope)), [migrated])
        XCTAssertEqual(try TripBackup.decode(TripBackup.encode([migrated])), [migrated])
    }
    @MainActor func testOnDiskMigrationAndReportingCurrencyLock() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
        func container() throws -> ModelContainer { try ModelContainer(for: SavedTrip.self, configurations: ModelConfiguration("MigrationTest", url: url, cloudKitDatabase: .none)) }
        var old = trip(); old.save(try expense(3000, currency: "USD", rate: 1))
        let data = try legacyData(old)
        try autoreleasepool {
            let c = try container(), context = ModelContext(c)
            context.insert(SavedTrip(id: old.id, payload: data)); try context.save()
        }
        try autoreleasepool {
            let c = try container(), store = try TripStore(container: c)
            XCTAssertEqual(store.trips[0].balances, old.balances)
            XCTAssertEqual(store.trips[0].schemaVersion, 2)
            let context = ModelContext(c)
            let payload = try context.fetch(FetchDescriptor<SavedTrip>())[0].payload
            XCTAssertEqual(try JSONDecoder().decode(TripRecord.self, from: payload).schemaVersion, 2)
            var edited = store.trips[0]; edited.currency = "EUR"
            XCTAssertThrowsError(try store.save(edited))
            edited = store.trips[0]; edited.expenses = []; try store.save(edited)
            edited.currency = "EUR"; XCTAssertThrowsError(try store.save(edited))
            XCTAssertEqual(store.trips[0].currency, "USD")
        }
        try autoreleasepool { XCTAssertEqual(try TripStore(container: container()).trips[0].schemaVersion, 2) }
    }
    func testStandaloneCurrencyPrecisionAndSharedCalculation() throws {
        let people = [Person(id: a.id, name: "Me", colorIndex: 0), Person(id: b.id, name: "Alex", colorIndex: 1), Person(id: c.id, name: "Sam", colorIndex: 2)]
        for (currency, total): (String, Decimal) in [("JPY", 1), ("KWD", Decimal(string: "0.001")!), ("XCG", Decimal(string: "10.01")!)] {
            let item = LineItem(name: "Meal", amount: total, category: .item)
            let receipt = ReceiptData(items: [item], surcharges: [], discounts: [], parsedTotal: nil)
            for mode in [SplitMode.even, .itemized] {
                let result = try SplitCalculator.calculate(receipt: receipt, people: people, mode: mode, assignments: [item.id: Set(people.map(\.id))], feeDistribution: .even, currency: currency)
                XCTAssertEqual(result.personResults.reduce(0) { $0 + $1.total }, total)
                for p in result.personResults { _ = try TripCurrency.minor(p.total, currency); XCTAssertGreaterThanOrEqual(p.total, 0) }
            }
        }
    }
}
