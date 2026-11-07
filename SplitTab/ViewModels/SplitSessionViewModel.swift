import SwiftUI
import Observation

@Observable
@MainActor
final class SplitSessionViewModel {
    var activityTripID: UUID?
    var historyError: String?
    private var previousAudit: Data?
    private var writingAudit = false

    private func audit(_ title: String) {
        guard !writingAudit else { return }
        writingAudit = true
        defer { writingAudit = false }
        do {
            let snapshot = BillActivitySnapshot(receipt: receipt,
                people: people.map { TripParticipant(id: $0.id, name: $0.name) }, assignments: assignments,
                currency: currencyCode, split: splitMode.rawValue, fees: feeDistribution.rawValue,
                discounts: discountDistribution.rawValue,
                result: splitResult.map { SplitCopyText.everyone($0, currency: currencyCode, title: receipt?.merchantName, breakdown: true) })
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(snapshot)
            guard data != previousAudit else { return }
            guard let store = TripStore.current else { throw TripIssue("History storage is unavailable. Reopen the app to preserve changes.") }
            try store.append(ActivityRecord(kind: "bill.changed", title: title, tripID: activityTripID,
                receiptID: receipt?.archiveID ?? previousAudit.flatMap { try? JSONDecoder().decode(BillActivitySnapshot.self, from: $0).receipt?.archiveID }, before: previousAudit, after: data))
            previousAudit = data
        } catch { historyError = "Could not preserve history: " + error.localizedDescription }
    }

    // MARK: - Receipt State
    var currencyCode = "USD" { didSet { audit("Changed currency") } }
    var calculationError: String?
    var receipt: ReceiptData? { didSet { audit("Edited receipt") } }
    var pendingReceiptCurrency: String?

    // MARK: - People
    var people: [Person] = [] { didSet { audit("Changed people") } }

    // MARK: - Split Configuration
    var splitMode: SplitMode = .itemized { didSet { audit("Changed split method") } }
    var feeDistribution: FeeDistribution = .proportional { didSet { audit("Changed fee distribution") } }
    var discountDistribution: FeeDistribution = .even { didSet { audit("Changed discount distribution") } }

    // MARK: - Item Assignments (lineItem.id → Set of person.id)
    var assignments: ItemAssignments = [:] { didSet { audit("Changed item assignments") } }

    // MARK: - Result
    var splitResult: SplitResult? { didSet { audit("Calculated shares") } }

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

    func toggleEveryone(itemId: UUID) {
        let all = Set(people.map(\.id))
        guard !all.isEmpty else { return }
        assignments[itemId] = all.isSubset(of: assignments[itemId] ?? []) ? [] : all
    }

    func isAssigned(itemId: UUID, personId: UUID) -> Bool {
        assignments[itemId]?.contains(personId) ?? false
    }

    func assignedPeople(for itemId: UUID) -> [Person] {
        guard let ids = assignments[itemId] else { return [] }
        return people.filter { ids.contains($0.id) }
    }

    var unassignedItemCount: Int {
        guard let receipt else { return 0 }
        return receipt.items.filter { item in
            (assignments[item.id] ?? []).isEmpty
        }.count
    }

    // MARK: - Receipt Editing

    func setReceipt(_ data: ReceiptData) {
        var source = data
        source.reconcileIncludedTax()
        let requested = currencyCode
        pendingReceiptCurrency = nil
        if source.currencyCode == nil { source.currencyCode = requested }
        if source.currencyCode != requested {
            if let converted = try? source.converted(to: requested) {
                receipt = converted
            } else {
                receipt = source
                currencyCode = source.currencyCode ?? requested
                pendingReceiptCurrency = requested
            }
        } else { receipt = source }
        assignments = [:]
    }

    func convertReceipt(to target: String, rate: Decimal? = nil) throws {
        guard var receipt else { return }
        if receipt.currencyCode == nil { receipt.currencyCode = currencyCode }
        self.receipt = try receipt.converted(to: target, rate: rate)
        currencyCode = target
        pendingReceiptCurrency = nil
    }

    func addLineItem(_ item: LineItem) {
        guard var r = receipt?.editableReceipt else { return }
        switch item.category {
        case .item, .unknown:
            r.items.append(item)
        case .tax, .tip, .fee:
            r.surcharges.append(item)
        case .discount:
            r.discounts.append(item)
        }
        _ = saveEditedReceipt(r)
    }

    @discardableResult
    func updateLineItem(_ item: LineItem) -> Bool {
        guard var r = receipt?.editableReceipt else { return false }
        if let idx = r.items.firstIndex(where: { $0.id == item.id }) {
            r.items[idx] = item
        } else if let idx = r.surcharges.firstIndex(where: { $0.id == item.id }) {
            r.surcharges[idx] = item
        } else if let idx = r.discounts.firstIndex(where: { $0.id == item.id }) {
            r.discounts[idx] = item
        }
        return saveEditedReceipt(r)
    }

    func deleteLineItem(_ item: LineItem) {
        guard var r = receipt?.editableReceipt else { return }
        r.items.removeAll { $0.id == item.id }
        r.surcharges.removeAll { $0.id == item.id }
        r.discounts.removeAll { $0.id == item.id }
        if saveEditedReceipt(r) { assignments.removeValue(forKey: item.id) }
    }

    @discardableResult
    private func saveEditedReceipt(_ source: ReceiptData) -> Bool {
        do {
            if source.currencyCode == nil || source.currencyCode == currencyCode {
                receipt = source
            } else {
                receipt = try source.converted(to: currencyCode, rate: receipt?.conversion?.rate)
            }
            calculationError = nil
            return true
        } catch {
            calculationError = error.localizedDescription
            return false
        }
    }

    // MARK: - Calculation

    func calculate() {
        guard let receipt, !people.isEmpty else { return }
        do {
        splitResult = try SplitCalculator.calculate(
            receipt: receipt,
            people: people,
            mode: splitMode,
            assignments: assignments,
            feeDistribution: feeDistribution,
            discountDistribution: discountDistribution,
            currency: currencyCode
        )
        calculationError = nil
        } catch { splitResult = nil; calculationError = error.localizedDescription }
    }

    // MARK: - Navigation Helpers

    func navigate(to route: SplitTabRoute) {
        navigationPath.append(route)
    }

    func navigateToResults() {
        calculate()
        if splitResult != nil { navigate(to: .results) }
    }

    // MARK: - Reset

    func startOver() {
        receipt = nil
        pendingReceiptCurrency = nil
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
