import Foundation
import SwiftData
import Observation

/// One atomic aggregate per trip, with a separately versioned backup envelope. Participant/expense/payment UUID references
/// live together in the payload so a save cannot persist half an allocation.
@Model final class SavedTrip {
    @Attribute(.unique) var id: UUID
    var payload: Data
    init(id: UUID, payload: Data) { self.id = id; self.payload = payload }
}

@MainActor @Observable final class TripStore {
    private let context: ModelContext
    private(set) var trips: [TripRecord] = []
    init(container: ModelContainer) throws {
        context = ModelContext(container)
        context.autosaveEnabled = false
        let records = try context.fetch(FetchDescriptor<SavedTrip>())
        var legacyIDs: Set<UUID> = []
        trips = try records.map {
            let decoded = try JSONDecoder().decode(TripRecord.self, from: $0.payload)
            if decoded.schemaVersion == nil { legacyIDs.insert($0.id) }
            let trip = try decoded.migrated()
            guard trip.id == $0.id else { throw TripIssue("Stored trip identity is invalid. The database has not been changed.") }
            try TripMath.validate(trip)
            return trip
        }
        // Validate the complete store before rewriting legacy payloads, atomically.
        let updates = try zip(records, trips).filter { legacyIDs.contains($0.0.id) }.map { ($0.0, try JSONEncoder().encode($0.1)) }
        do {
            for (record, data) in updates where record.payload != data { record.payload = data }
            if context.hasChanges { try context.save() }
        } catch { context.rollback(); throw error }
    }
    func save(_ trip: TripRecord) throws {
        if let previous = trips.first(where: { $0.id == trip.id }), previous.currencyLocked {
            guard previous.currency == trip.currency, trip.reportingCurrencyLocked == true else {
                throw TripIssue("Reporting currency is locked after the first record. Create another trip to use a different reporting currency.")
            }
        }
        try TripMath.validate(trip)
        let data = try JSONEncoder().encode(trip)
        do {
            let id = trip.id
            let matches = try context.fetch(FetchDescriptor<SavedTrip>(predicate: #Predicate { $0.id == id }))
            if let record = matches.first { record.payload = data }
            else { context.insert(SavedTrip(id: trip.id, payload: data)) }
            try context.save()
        } catch { context.rollback(); throw error }
        if let index = trips.firstIndex(where: { $0.id == trip.id }) { trips[index] = trip }
        else { trips.append(trip) }
    }
    /// A trip and all its records live in one aggregate; delete atomically.
    func delete(_ id: UUID) throws {
        do {
            let records = try context.fetch(FetchDescriptor<SavedTrip>(predicate: #Predicate { $0.id == id }))
            for record in records { context.delete(record) }
            try context.save()
        } catch { context.rollback(); throw error }
        trips.removeAll { $0.id == id }
    }
    /// Replacement is a single transaction, after full decoding and validation.
    func restore(_ data: Data) throws {
        let replacement = try TripBackup.decode(data)
        let encoded = try replacement.map { ($0.id, try JSONEncoder().encode($0)) }
        do {
            for record in try context.fetch(FetchDescriptor<SavedTrip>()) { context.delete(record) }
            // Reuse no old objects; unique identifiers are reconciled in one save.
            for (id, payload) in encoded { context.insert(SavedTrip(id: id, payload: payload)) }
            try context.save()
        } catch { context.rollback(); throw error }
        trips = replacement
    }
    func export() throws -> Data { try TripBackup.encode(trips) }
}
