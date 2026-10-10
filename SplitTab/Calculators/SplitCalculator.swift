import Foundation

/// Standalone receipts use the same minor-unit apportionment as trip expenses.
struct SplitCalculator {
    static func calculate(
        receipt: ReceiptData, people: [Person], mode: SplitMode,
        assignments: ItemAssignments, feeDistribution: FeeDistribution,
        discountDistribution: FeeDistribution = .even, currency: String = "USD"
    ) throws -> SplitResult {
        guard !people.isEmpty else { throw TripIssue("Add people before calculating.") }
        let ids = people.map(\.id)
        var effective = assignments
        let unassigned = receipt.items.filter { (effective[$0.id] ?? []).isEmpty }
        for item in unassigned { effective[item.id] = Set(ids) }
        var expense = TripExpense(title: "Bill", amount: try TripCurrency.minor(receipt.grandTotal, currency), payer: ids[0], participants: ids, mode: mode == .even ? .equal : .itemized, receipt: receipt, assignments: effective, fees: feeDistribution, discounts: discountDistribution)
        for line in receipt.items + receipt.surcharges + receipt.discounts { _ = try TripCurrency.minor(line.amount, currency) }
        expense.shares = try TripMath.shares(expense, currency: currency)
        let factor = TripCurrency.factor(currency)
        var base = Dictionary(uniqueKeysWithValues: ids.map { ($0, Int64(0)) })
        var lists: [UUID: [(item: LineItem, shareAmount: Decimal)]] = [:]
        for item in receipt.items {
            let selected = mode == .even ? ids : ids.filter { effective[item.id]?.contains($0) == true }
            let parts = try TripMath.allocate(TripCurrency.minor(item.amount, currency), ids: selected, weights: selected.map { _ in 1 })
            for (id, units) in parts { base[id, default: 0] += units; lists[id, default: []].append((item, Decimal(units) / factor)) }
        }
        let weights = ids.map { Decimal(base[$0] ?? 0) }
        func extras(_ value: Decimal, distribution: FeeDistribution) throws -> [UUID: Int64] {
            try TripMath.allocate(TripCurrency.minor(value, currency), ids: ids,
                                  weights: mode == .even || distribution == .even || weights.reduce(0, +) == 0 ? ids.map { _ in 1 } : weights)
        }
        let fees = try extras(receipt.surchargeTotal, distribution: feeDistribution)
        let discounts = try extras(receipt.discountTotal, distribution: discountDistribution)
        return SplitResult(personResults: people.map { p in
            PersonResult(id: p.id, name: p.name, avatarColorIndex: p.colorIndex,
                         assignedItems: mode == .even ? [] : lists[p.id] ?? [],
                         itemSubtotal: Decimal(base[p.id] ?? 0) / factor,
                         feeShare: Decimal(fees[p.id] ?? 0) / factor,
                         discountShare: Decimal(discounts[p.id] ?? 0) / factor,
                         total: Decimal(expense.shares[p.id] ?? 0) / factor)
        }, unassignedItems: mode == .even ? [] : unassigned, feeDistribution: feeDistribution, splitMode: mode)
    }
}
