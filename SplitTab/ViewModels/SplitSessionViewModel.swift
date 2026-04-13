import SwiftUI
import Observation

@Observable
final class SplitSessionViewModel {

    // MARK: - Receipt State
    var receipt: ReceiptData?

    // MARK: - People
    var people: [Person] = []

    // MARK: - Split Configuration
    var splitMode: SplitMode = .itemized
    var feeDistribution: FeeDistribution = .proportional
    var discountDistribution: FeeDistribution = .even

    // MARK: - Item Assignments (lineItem.id → Set of person.id)
    var assignments: ItemAssignments = [:]

    // MARK: - Result
    var splitResult: SplitResult?

    // MARK: - Navigation
    var navigationPath = NavigationPath()

    // MARK: - Scanner State
    var isShowingScanner = false
    var scanError: String?

    // MARK: - People Management

    func addPerson() {
        let index = people.count
        guard index < 8 else { return }
        people.append(Person(name: Person.defaultName(index: index), colorIndex: index))
    }

    func removePerson(at offsets: IndexSet) {
        let ids = offsets.map { people[$0].id }
        people.remove(atOffsets: offsets)
        for id in ids {
            for key in assignments.keys {
                assignments[key]?.remove(id)
            }
        }
    }

    func removePerson(id: UUID) {
        people.removeAll { $0.id == id }
        for key in assignments.keys {
            assignments[key]?.remove(id)
        }
    }

    func updatePersonName(_ personId: UUID, name: String) {
        guard let idx = people.firstIndex(where: { $0.id == personId }) else { return }
        people[idx].name = name
    }

    // MARK: - Assignment Management

    func toggleAssignment(itemId: UUID, personId: UUID) {
        if assignments[itemId] == nil { assignments[itemId] = [] }
        if assignments[itemId]!.contains(personId) {
            assignments[itemId]!.remove(personId)
        } else {
            assignments[itemId]!.insert(personId)
        }
    }

    func isAssigned(itemId: UUID, personId: UUID) -> Bool {
        assignments[itemId]?.contains(personId) ?? false
    }

    func assignedPeople(for itemId: UUID) -> [Person] {
        guard let ids = assignments[itemId] else { return [] }
        return people.filter { ids.contains($0.id) }
    }

    var unassignedFoodItemCount: Int {
        guard let receipt else { return 0 }
        return receipt.items.filter { item in
            (assignments[item.id] ?? []).isEmpty
        }.count
    }

    // MARK: - Receipt Editing

    func setReceipt(_ data: ReceiptData) {
        receipt = data
        assignments = [:]
    }

    func addLineItem(_ item: LineItem) {
        guard var r = receipt else { return }
        switch item.category {
        case .food, .unknown:
            r.items.append(item)
        case .tax, .tip, .fee:
            r.surcharges.append(item)
        case .discount:
            r.discounts.append(item)
        }
        receipt = r
    }

    func updateLineItem(_ item: LineItem) {
        guard var r = receipt else { return }
        if let idx = r.items.firstIndex(where: { $0.id == item.id }) {
            r.items[idx] = item
        } else if let idx = r.surcharges.firstIndex(where: { $0.id == item.id }) {
            r.surcharges[idx] = item
        } else if let idx = r.discounts.firstIndex(where: { $0.id == item.id }) {
            r.discounts[idx] = item
        }
        receipt = r
    }

    func deleteLineItem(_ item: LineItem) {
        guard var r = receipt else { return }
        r.items.removeAll { $0.id == item.id }
        r.surcharges.removeAll { $0.id == item.id }
        r.discounts.removeAll { $0.id == item.id }
        receipt = r
        assignments.removeValue(forKey: item.id)
    }

    // MARK: - Calculation

    func calculate() {
        guard let receipt, !people.isEmpty else { return }
        splitResult = SplitCalculator.calculate(
            receipt: receipt,
            people: people,
            mode: splitMode,
            assignments: assignments,
            feeDistribution: feeDistribution,
            discountDistribution: discountDistribution
        )
    }

    // MARK: - Navigation Helpers

    func navigate(to route: SplitTabRoute) {
        navigationPath.append(route)
    }

    func navigateToResults() {
        calculate()
        navigate(to: .results)
    }

    // MARK: - Reset

    func startOver() {
        receipt = nil
        people = []
        splitMode = .itemized
        feeDistribution = .proportional
        discountDistribution = .even
        assignments = [:]
        splitResult = nil
        navigationPath = NavigationPath()
        scanError = nil
    }
}
