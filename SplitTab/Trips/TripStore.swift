import Foundation
import SwiftData
import Observation

@Model final class SavedTrip {
    @Attribute(.unique) var id: UUID
    var payload: Data
    init(id: UUID, payload: Data) { self.id = id; self.payload = payload }
}

@MainActor @Observable final class TripStore {
    static private(set) var current: TripStore?
    private let context: ModelContext
    private(set) var trips: [TripRecord] = []
    private(set) var activity: [ActivityRecord] = []

    init(container: ModelContainer) throws {
        context = ModelContext(container)
        context.autosaveEnabled = false
        let records = try context.fetch(FetchDescriptor<SavedTrip>())
        let entries = try context.fetch(FetchDescriptor<SavedActivity>())
        activity = try entries.map { try JSONDecoder().decode(ActivityRecord.self, from: $0.payload) }
        trips = try records.map {
            let trip = try JSONDecoder().decode(TripRecord.self, from: $0.payload).migrated()
            guard trip.id == $0.id else { throw TripIssue("Stored trip identity is invalid. The database has not been changed.") }
            return trip
        }
        // Seed an honest starting snapshot. Prior deletions cannot be recovered.
        var seeds: [ActivityRecord] = []
        for trip in trips where !activity.contains(where: { $0.tripID == trip.id }) {
            seeds.append(ActivityRecord(kind: "trip.imported", title: "Existing trip: " + trip.name,
                                        tripID: trip.id, after: try JSONEncoder().encode(trip)))
        }
        do {
            for (record, trip) in zip(records, trips) { record.payload = try JSONEncoder().encode(trip) }
            for seed in seeds { context.insert(try SavedActivity(seed)) }
            if context.hasChanges { try context.save() }
        } catch { context.rollback(); throw error }
        activity += seeds
        Self.current = self
    }

    func append(_ entry: ActivityRecord) throws {
        do { context.insert(try SavedActivity(entry)); try context.save() }
        catch { context.rollback(); throw error }
        activity.append(entry)
    }

    func save(_ input: TripRecord) throws {
        var trip = input
        let previous = trips.first { $0.id == trip.id }
        if let previous, previous.currencyLocked {
            guard previous.currency == trip.currency, trip.reportingCurrencyLocked == true else {
                throw TripIssue("Currency is locked after the first record. Create another trip to use a different currency.")
            }
        }
        // Callers cannot rewrite history/checkpoints. Capture the last zero balance
        // before adding day-two expenses, including older trips without a checkpoint.
        trip.settlementBaseline = previous?.settlementBaseline
        if let previous, previous.settled, !previous.expenses.isEmpty || !previous.payments.isEmpty {
            trip.settlementBaseline = TripSettlementBaseline(date: previous.settlementBaseline?.date ?? previous.latestActivity, expenses: previous.expenses, payments: previous.payments)
        }
        if trip.settled, !trip.expenses.isEmpty || !trip.payments.isEmpty {
            let unchangedLedger = previous?.expenses == trip.expenses && previous?.payments == trip.payments
            trip.settlementBaseline = TripSettlementBaseline(
                date: unchangedLedger ? (previous?.settlementBaseline?.date ?? trip.latestActivity) : Date(),
                expenses: trip.expenses, payments: trip.payments)
        }
        try TripMath.validate(trip)
        let data = try JSONEncoder().encode(trip)
        let entry = ActivityRecord(kind: previous == nil ? "trip.created" : "trip.updated",
                                   title: changeTitle(previous, trip), tripID: trip.id,
                                   before: try previous.map { try JSONEncoder().encode($0) }, after: data)
        do {
            let id = trip.id
            let matches = try context.fetch(FetchDescriptor<SavedTrip>(predicate: #Predicate { $0.id == id }))
            if let record = matches.first { record.payload = data }
            else { context.insert(SavedTrip(id: trip.id, payload: data)) }
            context.insert(try SavedActivity(entry))
            try context.save()
        } catch { context.rollback(); throw error }
        if let index = trips.firstIndex(where: { $0.id == trip.id }) { trips[index] = trip }
        else { trips.append(trip) }
        activity.append(entry)
    }

    private func changeTitle(_ old: TripRecord?, _ trip: TripRecord) -> String {
        guard let old else { return "Created trip: " + trip.name }
        if let added = trip.expenses.first(where: { e in !old.expenses.contains { $0.id == e.id } }) { return "Added expense: " + added.title }
        if let removed = old.expenses.first(where: { e in !trip.expenses.contains { $0.id == e.id } }) { return "Deleted expense: " + removed.title }
        if let edited = trip.expenses.first(where: { e in old.expenses.contains { $0.id == e.id && $0 != e } }) { return "Edited expense: " + edited.title }
        if let added = trip.payments.first(where: { p in !old.payments.contains { $0.id == p.id } }) {
            return "Recorded payment: \(trip.person(added.sender)) → \(trip.person(added.recipient)), \(trip.money(added.balanceAmount))"
        }
        if old.payments != trip.payments { return "Corrected or undid payment: " + trip.name }
        return "Updated trip / participants: " + trip.name
    }

    /// Removing the live trip preserves every historical snapshot and receipt.
    func delete(_ id: UUID) throws {
        guard let trip = trips.first(where: { $0.id == id }) else { return }
        let entry = ActivityRecord(kind: "trip.deleted", title: "Deleted trip: " + trip.name,
                                   tripID: id, before: try JSONEncoder().encode(trip))
        do {
            for record in try context.fetch(FetchDescriptor<SavedTrip>(predicate: #Predicate { $0.id == id })) { context.delete(record) }
            context.insert(try SavedActivity(entry))
            try context.save()
        } catch { context.rollback(); throw error }
        trips.removeAll { $0.id == id }
        activity.append(entry)
    }

    /// Replace live trips but merge append-only evidence. Restores never erase history.
    func restore(_ data: Data) throws {
        let replacement = try TripBackup.decode(data)
        let envelope = try JSONDecoder().decode(TripBackup.self, from: data)
        let imported = envelope.activity ?? []
        guard Set(imported.map(\.id)).count == imported.count else { throw TripIssue("Duplicate history entries in backup.") }
        for entry in imported {
            if let existing = activity.first(where: { $0.id == entry.id }), existing != entry {
                throw TripIssue("Backup conflicts with protected history. No records were changed.")
            }
        }
        let additions = imported.filter { entry in !activity.contains { $0.id == entry.id } }
        let event = ActivityRecord(kind: "backup.restored", title: "Restored backup (\(replacement.count) trips)",
                                   before: try JSONEncoder().encode(trips), after: try JSONEncoder().encode(replacement))
        do {
            for record in try context.fetch(FetchDescriptor<SavedTrip>()) { context.delete(record) }
            for trip in replacement { context.insert(SavedTrip(id: trip.id, payload: try JSONEncoder().encode(trip))) }
            for entry in additions + [event] { context.insert(try SavedActivity(entry)) }
            try context.save()
        } catch { context.rollback(); throw error }
        trips = replacement
        activity += additions + [event]
    }
    func export() throws -> Data {
        try append(ActivityRecord(kind: "backup.exported", title: "Created backup with trips, receipts and history"))
        return try TripBackup.encode(trips, activity: activity)
    }
}
