import Foundation

struct TripIssue: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

enum TripCurrency {
    // XCG: Caribbean guilder, verified with CBCS. Explicit minor-unit precision.
    static let codes = ["USD", "XCG", "EUR", "GBP", "CAD", "AUD", "CHF", "SGD", "NZD", "MXN", "INR", "JPY", "KWD"]
    static func digits(_ code: String) -> Int { code == "JPY" ? 0 : code == "KWD" ? 3 : 2 }
    static func factor(_ code: String) -> Decimal { pow(Decimal(10), digits(code)) }
    static func minor(_ value: Decimal, _ code: String) throws -> Int64 {
        let scaled = value * factor(code)
        var input = scaled, rounded = Decimal()
        NSDecimalRound(&rounded, &input, 0, .plain)
        guard !value.isNaN, abs(value) <= 1_000_000_000, scaled == rounded else {
            throw TripIssue("Enter a valid amount with at most \(digits(code)) decimal places (maximum 1 billion).")
        }
        return NSDecimalNumber(decimal: rounded).int64Value
    }
    static func parse(_ text: String) throws -> Decimal {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Commas group thousands when there are exactly three digits per group.
        // A single comma with one or two trailing digits remains a decimal separator.
        let grouped = value.range(of: #"^-?[1-9][0-9]{0,2}(,[0-9]{3})+(\.[0-9]+)?$"#, options: .regularExpression) != nil
        let normalized = grouped ? value.replacingOccurrences(of: ",", with: "") : value.replacingOccurrences(of: ",", with: ".")
        guard normalized.range(of: #"^-?[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil,
              let result = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")), !result.isNaN else {
            throw TripIssue("Enter a valid number, such as 1,250.50.")
        }
        return result
    }
    static func format(_ minor: Int64, _ code: String) -> String {
        formatDecimal(Decimal(minor) / factor(code), code)
    }
    static func formatDecimal(_ value: Decimal, _ code: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = digits(code)
        f.maximumFractionDigits = digits(code)
        return code + " " + (f.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)")
    }
}

/// Rate direction is always: 1 original currency = rate reporting currency.
struct TripFX: Codable, Equatable {
    var currency: String
    var reportingCurrency: String
    var rate: Decimal
    var convertedAmount: Int64
    var direction: String { "1 \(currency) = \(NSDecimalNumber(decimal: rate).stringValue) \(reportingCurrency)" }
    static func make(amount: Int64, currency: String, reporting: String, rate: Decimal) throws -> TripFX {
        guard TripCurrency.codes.contains(currency), TripCurrency.codes.contains(reporting), amount > 0,
              !rate.isNaN, rate > 0, rate <= 1_000_000, currency != reporting || rate == 1 else {
            throw TripIssue("Enter a positive conversion rate. Same-currency amounts must use a rate of 1.")
        }
        let original = Decimal(amount) / TripCurrency.factor(currency)
        _ = try TripCurrency.minor(original, currency)
        var raw = original * rate, rounded = Decimal()
        guard !raw.isNaN else { throw TripIssue("Invalid converted amount.") }
        NSDecimalRound(&rounded, &raw, TripCurrency.digits(reporting), .plain)
        let converted = try TripCurrency.minor(rounded, reporting)
        guard converted > 0 else { throw TripIssue("The converted amount rounds to zero. Increase the amount or correct the rate.") }
        return TripFX(currency: currency, reportingCurrency: reporting, rate: rate, convertedAmount: converted)
    }
}

struct TripParticipant: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
}
enum TripStatus: String, Codable { case active, ended, archived }
enum TripSplit: String, Codable, CaseIterable, Identifiable {
    case equal = "Equal", itemized = "Itemized", exact = "Exact amounts", percentage = "Percentages", weights = "Weights"
    var id: String { rawValue }
}
struct TripExpense: Codable, Identifiable, Equatable {
    var id = UUID()
    var createdAt = Date()
    var title = ""
    var amount: Int64 = 0
    var payer: UUID
    var participants: [UUID]
    var mode: TripSplit = .equal
    var inputs: [UUID: Decimal] = [:]
    var receipt: ReceiptData? = nil
    var assignments: [UUID: Set<UUID>] = [:]
    var fees: FeeDistribution = .proportional
    var discounts: FeeDistribution = .even
    var shares: [UUID: Int64] = [:] // Original currency; never overwritten by conversion.
    var fx: TripFX? = nil // Absent only in legacy records or unsaved drafts.
    var reportingShares: [UUID: Int64]? = nil
    var balanceAmount: Int64 { fx?.convertedAmount ?? amount }
    var balanceShares: [UUID: Int64] { reportingShares ?? shares }
    mutating func convert(currency: String, reporting: String, rate: Decimal) throws {
        let conversion = try TripFX.make(amount: amount, currency: currency, reporting: reporting, rate: rate)
        reportingShares = try TripMath.convertedShares(self, total: conversion.convertedAmount)
        fx = conversion
    }
}
struct TripPayment: Codable, Identifiable, Equatable {
    var id = UUID()
    var createdAt = Date()
    var sender: UUID
    var recipient: UUID
    var amount: Int64
    var note = ""
    var fx: TripFX? = nil
    var balanceAmount: Int64 { fx?.convertedAmount ?? amount }
}
struct TripRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var currency = "USD"
    var participants: [TripParticipant]
    var me: UUID
    var status: TripStatus = .active
    var expenses: [TripExpense] = []
    var payments: [TripPayment] = []
    var schemaVersion: Int? = 2
    var reportingCurrencyLocked: Bool? = false
    var currencyLocked: Bool { reportingCurrencyLocked == true || !expenses.isEmpty || !payments.isEmpty }
    var latestActivity: Date { (expenses.map(\.createdAt) + payments.map(\.createdAt)).max() ?? .distantPast }
    /// v1 had exactly one currency. Missing FX is migrated only from that schema.
    func migrated() throws -> TripRecord {
        var t = self
        if schemaVersion == nil {
            guard expenses.allSatisfy({ $0.fx == nil && $0.reportingShares == nil }), payments.allSatisfy({ $0.fx == nil }) else {
                throw TripIssue("Legacy data contains unexpected conversion fields.")
            }
            for i in t.expenses.indices {
                t.expenses[i].fx = try TripFX.make(amount: t.expenses[i].amount, currency: currency, reporting: currency, rate: 1)
                t.expenses[i].reportingShares = t.expenses[i].shares
            }
            for i in t.payments.indices {
                t.payments[i].fx = try TripFX.make(amount: t.payments[i].amount, currency: currency, reporting: currency, rate: 1)
            }
            t.schemaVersion = 2
            t.reportingCurrencyLocked = !expenses.isEmpty || !payments.isEmpty
        }
        try TripMath.validate(t)
        return t
    }
    func person(_ id: UUID) -> String { participants.first { $0.id == id }?.name ?? "Unknown participant" }
    func money(_ amount: Int64) -> String { TripCurrency.format(amount, currency) }
    var balances: [UUID: Int64] { TripMath.balances(self) }
    var settled: Bool { balances.values.allSatisfy { $0 == 0 } }
    mutating func normalizeStatus() { if status != .active { status = settled ? .archived : .ended } }
    mutating func save(_ input: TripExpense) {
        var expense = input
        if expense.fx == nil {
            expense.fx = TripFX(currency: currency, reportingCurrency: currency, rate: 1, convertedAmount: expense.amount)
            expense.reportingShares = expense.shares
        }
        reportingCurrencyLocked = true
        if let i = expenses.firstIndex(where: { $0.id == expense.id }) { expenses[i] = expense }
        else { expenses.append(expense) }
        normalizeStatus()
    }
    mutating func save(_ input: TripPayment) {
        var payment = input
        if payment.fx == nil { payment.fx = TripFX(currency: currency, reportingCurrency: currency, rate: 1, convertedAmount: payment.amount) }
        reportingCurrencyLocked = true
        if let i = payments.firstIndex(where: { $0.id == payment.id }) { payments[i] = payment }
        else { payments.append(payment) }
        normalizeStatus()
    }
}
struct TripTransfer: Identifiable, Equatable {
    var sender: UUID
    var recipient: UUID
    var amount: Int64
    var id: String { sender.uuidString + recipient.uuidString }
}

enum TripMath {
    /// Largest remainders, with stable participant order breaking ties. No floating point.
    static func allocate(_ total: Int64, ids: [UUID], weights: [Decimal]) throws -> [UUID: Int64] {
        guard !ids.isEmpty, ids.count == weights.count, Set(ids).count == ids.count,
              weights.allSatisfy({ !$0.isNaN && $0 >= 0 && $0 <= 1_000_000_000_000 }), weights.reduce(0, +) > 0 else {
            throw TripIssue("Choose participants and valid positive allocation weights.")
        }
        let sum = weights.reduce(0, +), magnitude = abs(total)
        var units: [Int64] = [], fractions: [Decimal] = []
        for weight in weights {
            let raw = Decimal(magnitude) * weight / sum
            var input = raw, floor = Decimal()
            NSDecimalRound(&floor, &input, 0, .down)
            units.append(NSDecimalNumber(decimal: floor).int64Value)
            fractions.append(raw - floor)
        }
        let order = ids.indices.sorted { fractions[$0] == fractions[$1] ? $0 < $1 : fractions[$0] > fractions[$1] }
        let remainder = magnitude - units.reduce(0, +)
        guard remainder >= 0, remainder <= Int64(ids.count) else { throw TripIssue("Unable to reconcile this allocation.") }
        for index in 0..<Int(remainder) { units[order[index]] += 1 }
        return Dictionary(uniqueKeysWithValues: ids.indices.map { (ids[$0], total < 0 ? -units[$0] : units[$0]) })
    }
    static func shares(_ e: TripExpense, currency: String) throws -> [UUID: Int64] {
        let ids = e.participants
        guard e.amount > 0, e.amount <= 1_000_000_000_000, !ids.isEmpty, Set(ids).count == ids.count else { throw TripIssue("Enter a positive total and select who shares it.") }
        switch e.mode {
        case .equal: return try allocate(e.amount, ids: ids, weights: ids.map { _ in 1 })
        case .exact:
            guard Set(e.inputs.keys) == Set(ids) else { throw TripIssue("Enter an amount for every selected person.") }
            let values = try ids.map { try TripCurrency.minor(e.inputs[$0]!, currency) }
            guard values.allSatisfy({ $0 >= 0 }), values.reduce(0, +) == e.amount else { throw TripIssue("Exact shares must add up to the expense total.") }
            return Dictionary(uniqueKeysWithValues: zip(ids, values))
        case .percentage, .weights:
            guard Set(e.inputs.keys) == Set(ids) else { throw TripIssue("Enter a value for every selected person.") }
            let weights = ids.map { e.inputs[$0]! }
            guard weights.allSatisfy({ !$0.isNaN && (e.mode == .weights ? $0 > 0 : $0 >= 0) && $0 <= 1_000_000_000 }) else { throw TripIssue("Weights must be positive; percentages cannot be negative.") }
            if e.mode == .percentage && weights.reduce(0, +) != 100 { throw TripIssue("Percentages must total exactly 100%.") }
            return try allocate(e.amount, ids: ids, weights: weights)
        case .itemized:
            guard let r = e.receipt, !r.items.isEmpty else { throw TripIssue("Add receipt items first.") }
            let all = r.items + r.surcharges + r.discounts
            guard Set(all.map(\.id)).count == all.count, all.count <= 10_000,
                  Set(e.assignments.keys).isSubset(of: Set(r.items.map(\.id))) else { throw TripIssue("Invalid receipt item references.") }
            for line in all { _ = try TripCurrency.minor(line.amount, currency) }
            guard r.items.allSatisfy({ $0.amount >= 0 }), r.surcharges.allSatisfy({ $0.amount >= 0 }), r.discounts.allSatisfy({ $0.amount <= 0 }),
                  try TripCurrency.minor(r.grandTotal, currency) == e.amount else { throw TripIssue("Receipt items, fees and discounts must match the total and use valid signs.") }
            var result = Dictionary(uniqueKeysWithValues: ids.map { ($0, Int64(0)) })
            for item in r.items {
                let assigned = e.assignments[item.id] ?? []
                guard !assigned.isEmpty, assigned.isSubset(of: Set(ids)) else { throw TripIssue("Assign every item to selected participants.") }
                let selected = ids.filter { assigned.contains($0) }
                let shares = try allocate(TripCurrency.minor(item.amount, currency), ids: selected, weights: selected.map { _ in 1 })
                for (id, share) in shares { result[id, default: 0] += share }
            }
            let base = result
            for (total, distribution) in [(r.surchargeTotal, e.fees), (r.discountTotal, e.discounts)] {
                let weights = ids.map { distribution == .even || base.values.reduce(0, +) == 0 ? Decimal(1) : Decimal(base[$0]!) }
                let parts = try allocate(TripCurrency.minor(total, currency), ids: ids, weights: weights)
                for (id, share) in parts { result[id, default: 0] += share }
            }
            guard result.values.allSatisfy({ $0 >= 0 }), result.values.reduce(0, +) == e.amount else { throw TripIssue("This discount allocation makes a share negative. Adjust its distribution or items.") }
            return result
        }
    }
    static func convertedShares(_ e: TripExpense, total: Int64) throws -> [UUID: Int64] {
        guard e.shares.values.reduce(0, +) == e.amount else { throw TripIssue("Original shares do not match the total.") }
        return try allocate(total, ids: e.participants, weights: e.participants.map { Decimal(e.shares[$0] ?? 0) })
    }
    static func balances(_ trip: TripRecord) -> [UUID: Int64] {
        var values = Dictionary(uniqueKeysWithValues: trip.participants.map { ($0.id, Int64(0)) })
        for e in trip.expenses {
            values[e.payer, default: 0] += e.balanceAmount
            for (id, share) in e.balanceShares { values[id, default: 0] -= share }
        }
        for p in trip.payments {
            values[p.sender, default: 0] += p.balanceAmount
            values[p.recipient, default: 0] -= p.balanceAmount
        }
        return values
    }
    /// Keep expense debts between their original participants. Payments reduce those
    /// debts (or create a refund credit). Cancel circular obligations so historical
    /// payments via other people cannot leave a fully settled trip owing money.
    static func settlements(_ trip: TripRecord) -> [TripTransfer] {
        let ids = trip.participants.map(\.id)
        let index = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        var debts = Array(repeating: Array(repeating: Int64(0), count: ids.count), count: ids.count)
        func add(_ sender: UUID, _ recipient: UUID, _ amount: Int64) {
            guard sender != recipient, let a = index[sender], let b = index[recipient] else { return }
            debts[a][b] += amount
            debts[b][a] -= amount
        }
        for expense in trip.expenses {
            for (person, share) in expense.balanceShares { add(person, expense.payer, share) }
        }
        for payment in trip.payments { add(payment.sender, payment.recipient, -payment.balanceAmount) }
        for a in ids.indices {
            for b in ids.indices { debts[a][b] = max(0, debts[a][b]) }
        }

        // Stable participant order determines which cycle is cancelled first.
        // Removing the same amount from every edge preserves every net balance.
        func cycle() -> [Int]? {
            var state = Array(repeating: 0, count: ids.count)
            var path: [Int] = []
            func visit(_ node: Int) -> [Int]? {
                state[node] = 1; path.append(node)
                for next in ids.indices where debts[node][next] > 0 {
                    if state[next] == 1, let start = path.firstIndex(of: next) {
                        return Array(path[start...])
                    }
                    if state[next] == 0, let found = visit(next) { return found }
                }
                path.removeLast(); state[node] = 2
                return nil
            }
            for node in ids.indices where state[node] == 0 {
                if let found = visit(node) { return found }
            }
            return nil
        }
        while let nodes = cycle() {
            let edges = nodes.indices.map { (nodes[$0], nodes[($0 + 1) % nodes.count]) }
            let amount = edges.map { debts[$0.0][$0.1] }.min()!
            for (a, b) in edges { debts[a][b] -= amount }
        }
        return ids.indices.flatMap { recipient in
            ids.indices.compactMap { sender in
                debts[sender][recipient] > 0
                    ? TripTransfer(sender: ids[sender], recipient: ids[recipient], amount: debts[sender][recipient]) : nil
            }
        }
    }

    /// Signed reporting-currency contributions explaining a displayed repayment.
    static func settlementBreakdown(_ trip: TripRecord, transfer: TripTransfer) -> [(label: String, amount: Int64)] {
        var lines: [(label: String, amount: Int64)] = []
        for expense in trip.expenses {
            if expense.payer == transfer.recipient, let share = expense.balanceShares[transfer.sender], share > 0 {
                lines.append((expense.title, share))
            } else if expense.payer == transfer.sender, let share = expense.balanceShares[transfer.recipient], share > 0 {
                lines.append(("Offset: " + expense.title + " paid by " + trip.person(transfer.sender), -share))
            }
        }
        for payment in trip.payments {
            if payment.sender == transfer.sender && payment.recipient == transfer.recipient {
                lines.append(("Payment already recorded", -payment.balanceAmount))
            } else if payment.sender == transfer.recipient && payment.recipient == transfer.sender {
                lines.append(("Payment received from " + trip.person(transfer.recipient), payment.balanceAmount))
            }
        }
        let adjustment = transfer.amount - lines.reduce(Int64(0)) { $0 + $1.amount }
        if adjustment != 0 { lines.append(("Offset through other participants", adjustment)) }
        return lines
    }
    static func settlementText(_ trip: TripRecord, sender: UUID? = nil, breakdown: Bool) -> String {
        let transfers = settlements(trip).filter { sender == nil || $0.sender == sender }
        var lines = [SplitCopyText.cleanLabel(trip.name), "Repayments"]
        if transfers.isEmpty { lines += ["", "Nothing left to pay."] }
        for person in trip.participants {
            let outgoing = transfers.filter { $0.sender == person.id }
            guard !outgoing.isEmpty else { continue }
            lines += ["", SplitCopyText.cleanLabel(person.name)]
            for (index, transfer) in outgoing.enumerated() {
                if breakdown && index > 0 { lines.append("") }
                lines.append("• \(SplitCopyText.cleanLabel(person.name)) owes \(SplitCopyText.cleanLabel(trip.person(transfer.recipient))) \(trip.money(transfer.amount))")
                if breakdown {
                    for line in settlementBreakdown(trip, transfer: transfer) {
                        lines.append("  • \(SplitCopyText.cleanLabel(line.label)): \(trip.money(line.amount))")
                    }
                }
            }
            lines.append("Total to pay: \(trip.money(outgoing.reduce(0) { $0 + $1.amount }))")
        }
        if sender == nil && !transfers.isEmpty {
            lines += ["", "Total to repay: \(trip.money(transfers.reduce(0) { $0 + $1.amount }))"]
        }
        return lines.joined(separator: "\n")
    }

    static func validate(_ trip: TripRecord) throws {
        let ids = Set(trip.participants.map(\.id))
        guard trip.schemaVersion == 2, trip.reportingCurrencyLocked != nil,
              (!trip.expenses.isEmpty || !trip.payments.isEmpty) ? trip.reportingCurrencyLocked == true : true,
              !trip.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, TripCurrency.codes.contains(trip.currency),
              !ids.isEmpty, ids.count == trip.participants.count, ids.contains(trip.me), trip.participants.count <= 200,
              trip.participants.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              trip.expenses.count <= 10_000, trip.payments.count <= 10_000,
              Set(trip.expenses.map(\.id)).count == trip.expenses.count, Set(trip.payments.map(\.id)).count == trip.payments.count else { throw TripIssue("Invalid trip, currency, participant or duplicate record.") }
        for e in trip.expenses {
            guard !e.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, ids.contains(e.payer), Set(e.participants).isSubset(of: ids),
                  let fx = e.fx, fx.reportingCurrency == trip.currency,
                  try TripFX.make(amount: e.amount, currency: fx.currency, reporting: trip.currency, rate: fx.rate) == fx,
                  try shares(e, currency: fx.currency) == e.shares,
                  try convertedShares(e, total: fx.convertedAmount) == e.reportingShares else { throw TripIssue("Invalid expense or saved allocation: \(e.title).") }
        }
        for p in trip.payments {
            guard ids.contains(p.sender), ids.contains(p.recipient), p.sender != p.recipient, p.amount > 0, p.amount <= 1_000_000_000_000,
                  let fx = p.fx, fx.reportingCurrency == trip.currency,
                  try TripFX.make(amount: p.amount, currency: fx.currency, reporting: trip.currency, rate: fx.rate) == fx else { throw TripIssue("Payments need distinct participants and a positive amount.") }
        }
        guard balances(trip).values.reduce(0, +) == 0, trip.status != .archived || trip.settled else { throw TripIssue("Invalid trip balance or archive state.") }
    }
    static func summary(_ t: TripRecord) -> String {
        var lines = [t.name + " (" + t.currency + ")", "Total spending: \(t.money(t.expenses.reduce(0) { $0 + $1.balanceAmount }))", "", "Expenses"]
        for e in t.expenses {
            lines.append("\(e.title): \(TripCurrency.format(e.amount, e.fx?.currency ?? t.currency)) — paid by \(t.person(e.payer)); \(e.mode.rawValue)")
            if let fx = e.fx { lines.append("  \(fx.direction); reporting total: \(t.money(fx.convertedAmount))") }
            for id in e.participants { lines.append("  \(t.person(id)): \(TripCurrency.format(e.shares[id] ?? 0, e.fx?.currency ?? t.currency)) → \(t.money(e.balanceShares[id] ?? 0))") }
            if e.mode == .itemized, let r = e.receipt {
                for item in r.items { lines.append("  \(item.name): \(TripCurrency.formatDecimal(item.amount, e.fx?.currency ?? t.currency)) [\(e.participants.filter { e.assignments[item.id]?.contains($0) == true }.map { t.person($0) }.joined(separator: ", "))]") }
                for item in r.surcharges + r.discounts { lines.append("  \(item.name): \(TripCurrency.formatDecimal(item.amount, e.fx?.currency ?? t.currency))") }
                lines.append("  Fees: \(e.fees.rawValue); discounts: \(e.discounts.rawValue)")
            }
        }
        lines += ["", "Recorded payments (already included in balances)"]
        for p in t.payments {
            if let fx = p.fx { lines.append("\(fx.direction); balance effect: \(t.money(fx.convertedAmount))") }
            lines.append("\(t.person(p.sender)) → \(t.person(p.recipient)): \(TripCurrency.format(p.amount, p.fx?.currency ?? t.currency))\(p.note.isEmpty ? "" : " — " + p.note)") }
        lines += ["", "Net balances"]
        for p in t.participants { let b = t.balances[p.id] ?? 0; lines.append("\(p.name): \(b == 0 ? "settled" : b > 0 ? "gets back " + t.money(b) : "owes " + t.money(-b))") }
        lines += ["", "Suggested direct payments (not yet received)"]
        for p in settlements(t) { lines.append("\(t.person(p.sender)) pays \(t.person(p.recipient)) \(t.money(p.amount))") }
        if t.settled { lines.append("Everyone is settled.") }
        lines.append("Payments happen outside SplitTab. Suggestions are not recorded payments.")
        return lines.joined(separator: "\n")
    }
}

struct TripBackup: Codable {
    var format = "SplitTab.Trips"
    var version = 2
    var exportedAt = Date()
    var trips: [TripRecord]
    func validated() throws -> [TripRecord] {
        guard format == "SplitTab.Trips", (version == 1 || version == 2), trips.count <= 1000, Set(trips.map(\.id)).count == trips.count else { throw TripIssue("Unsupported backup version or duplicate trips.") }
        guard trips.allSatisfy({ version == 1 ? $0.schemaVersion == nil : $0.schemaVersion == 2 }) else { throw TripIssue("Backup and trip schema versions do not match.") }
        return try trips.map { try $0.migrated() }
    }
    static func decode(_ data: Data) throws -> [TripRecord] {
        guard data.count <= 50_000_000 else { throw TripIssue("Backup exceeds the 50 MB limit.") }
        return try JSONDecoder().decode(Self.self, from: data).validated()
    }
    static func encode(_ trips: [TripRecord]) throws -> Data {
        let backup = Self(trips: trips)
        _ = try backup.validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }
}
