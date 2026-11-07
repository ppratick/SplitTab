import Foundation
import SwiftData

/// Append-only evidence, separate from the live trip aggregate. No deletion API.
nonisolated struct ActivityRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var kind: String
    var title: String
    var tripID: UUID? = nil
    var receiptID: UUID? = nil
    var before: Data? = nil
    var after: Data? = nil
    var image: Data? = nil
}

@Model final class SavedActivity {
    @Attribute(.unique) var id: UUID
    @Attribute(.externalStorage) var payload: Data
    init(_ record: ActivityRecord) throws {
        id = record.id
        payload = try JSONEncoder().encode(record)
    }
}

struct BillActivitySnapshot: Codable {
    var receipt: ReceiptData?
    var people: [TripParticipant]
    var assignments: [UUID: Set<UUID>]
    var currency: String
    var split: String
    var fees: String
    var discounts: String
    var result: String?
}
