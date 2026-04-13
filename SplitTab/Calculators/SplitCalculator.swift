import Foundation

struct SplitCalculator {

    static func calculate(
        receipt: ReceiptData,
        people: [Person],
        mode: SplitMode,
        assignments: ItemAssignments,
        feeDistribution: FeeDistribution,
        discountDistribution: FeeDistribution = .even
    ) -> SplitResult {
        guard !people.isEmpty else {
            return SplitResult(personResults: [], unassignedItems: receipt.items,
                               feeDistribution: feeDistribution, splitMode: mode)
        }
        switch mode {
        case .even:
            return calculateEven(receipt: receipt, people: people, feeDistribution: feeDistribution)
        case .itemized:
            return calculateItemized(receipt: receipt, people: people,
                                     assignments: assignments, feeDistribution: feeDistribution,
                                     discountDistribution: discountDistribution)
        }
    }

    // MARK: - Even Split

    private static func calculateEven(
        receipt: ReceiptData,
        people: [Person],
        feeDistribution: FeeDistribution
    ) -> SplitResult {
        let n = Decimal(people.count)
        let perPerson = round2(receipt.grandTotal / n)
        let remainder = receipt.grandTotal - perPerson * n

        let results = people.enumerated().map { idx, person -> PersonResult in
            let adj: Decimal = idx == 0 ? remainder : 0
            return PersonResult(
                id: person.id,
                name: person.name,
                avatarColorIndex: person.colorIndex,
                assignedItems: [],
                itemSubtotal: round2(receipt.itemSubtotal / n),
                feeShare: round2(receipt.surchargeTotal / n),
                discountShare: round2(receipt.discountTotal / n),
                total: perPerson + adj
            )
        }
        return SplitResult(personResults: results, unassignedItems: [],
                           feeDistribution: .even, splitMode: .even)
    }

    // MARK: - Itemized Split

    private static func calculateItemized(
        receipt: ReceiptData,
        people: [Person],
        assignments: ItemAssignments,
        feeDistribution: FeeDistribution,
        discountDistribution: FeeDistribution
    ) -> SplitResult {
        let n = Decimal(people.count)
        var personItems: [UUID: Decimal] = Dictionary(uniqueKeysWithValues: people.map { ($0.id, Decimal(0)) })
        var personItemList: [UUID: [(item: LineItem, shareAmount: Decimal)]] = Dictionary(uniqueKeysWithValues: people.map { ($0.id, []) })
        var unassigned: [LineItem] = []

        // Distribute assigned items
        for item in receipt.items {
            let assignees = Array(assignments[item.id] ?? [])
            guard !assignees.isEmpty else {
                unassigned.append(item)
                continue
            }
            let share = round2(item.amount / Decimal(assignees.count))
            let remainder = item.amount - share * Decimal(assignees.count)
            for (idx, pid) in assignees.enumerated() {
                let adj: Decimal = idx == 0 ? remainder : 0
                let finalShare = share + adj
                personItems[pid, default: 0] += finalShare
                personItemList[pid, default: []].append((item: item, shareAmount: finalShare))
            }
        }

        // Unassigned items split evenly as fallback
        let unassignedTotal = unassigned.reduce(Decimal(0)) { $0 + $1.amount }
        let unassignedPerPerson = round2(unassignedTotal / n)

        let itemSubtotalForProportion = receipt.itemSubtotal

        let results = people.map { person -> PersonResult in
            let myItems = personItems[person.id, default: 0] + unassignedPerPerson

            let feeShare: Decimal
            let discountShare: Decimal

            switch feeDistribution {
            case .even:
                feeShare = round2(receipt.surchargeTotal / n)
            case .proportional:
                let proportion: Decimal = itemSubtotalForProportion > 0
                    ? myItems / itemSubtotalForProportion
                    : Decimal(1) / n
                feeShare = round2(receipt.surchargeTotal * proportion)
            }

            switch discountDistribution {
            case .even:
                discountShare = round2(receipt.discountTotal / n)
            case .proportional:
                let proportion: Decimal = itemSubtotalForProportion > 0
                    ? myItems / itemSubtotalForProportion
                    : Decimal(1) / n
                discountShare = round2(receipt.discountTotal * proportion)
            }

            let total = max(0, myItems + feeShare + discountShare)
            return PersonResult(
                id: person.id,
                name: person.name,
                avatarColorIndex: person.colorIndex,
                assignedItems: personItemList[person.id, default: []],
                itemSubtotal: myItems,
                feeShare: feeShare,
                discountShare: discountShare,
                total: total
            )
        }

        return SplitResult(personResults: results, unassignedItems: unassigned,
                           feeDistribution: feeDistribution, splitMode: .itemized)
    }

    // MARK: - Rounding

    private static func round2(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 2, .plain)
        return result
    }
}
