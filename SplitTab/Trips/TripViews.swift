import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TripBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct TripRootView: View {
    @State private var store: TripStore?
    @State private var failure: String?
    var body: some View {
        OpeningHomeView(store: store, failure: failure, retry: openStore)
        .tint(.splitAccent)
        .preferredColorScheme(.dark)
        .task { if store == nil { openStore() } }
    }
    private func openStore() {
        do {
            let configuration = ModelConfiguration("SplitTabTrips", cloudKitDatabase: .none)
            let container = try ModelContainer(for: SavedTrip.self, SavedActivity.self, configurations: configuration)
            store = try TripStore(container: container)
            failure = nil
        } catch { failure = "Your database has not been reset. \(error.localizedDescription)" }
    }
}

struct TripListView: View {
    @AppStorage("recentTripID") private var recentTripID = ""
    @State private var deletingTrip: TripRecord?
    @Environment(\.dismiss) private var dismiss
    @Environment(TripStore.self) private var store
    @State private var create = false
    @State private var exporting = false
    @State private var importing = false
    @State private var document: TripBackupDocument?
    @State private var pendingBackup: Data?
    @State private var restoreDescription = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                if store.trips.isEmpty {
                    ContentUnavailableView("Your trips", systemImage: "suitcase", description: Text("Create a trip and manage everyone's expenses and payments here. No one else needs the app."))
                }
                ForEach([TripStatus.active, .ended, .archived], id: \.self) { status in
                    let trips = store.trips.filter { $0.status == status }
                    if !trips.isEmpty {
                        Section(status == .active ? "Active" : status == .ended ? "Ended · balances outstanding" : "Archived · settled") {
                            ForEach(trips) { trip in
                                NavigationLink { TripDetailView(tripID: trip.id) } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(trip.name).font(.headline)
                                        Text("\(trip.participants.count) people · \(trip.currency)").font(.caption).foregroundStyle(.secondary)
                                        Text(tripPosition(trip.balances[trip.me] ?? 0, trip: trip, me: true)).foregroundStyle(Color.splitAccent)
                                    }.padding(.vertical, 4)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button("Delete", role: .destructive) { deletingTrip = trip }
                                }
                            }
                        }
                    }
                }
            }
            .tripStyle()
            .navigationTitle("Trips")
            .toolbar {
                ToolbarItem(placement: .primaryAction) { Button("Create Trip", systemImage: "plus") { create = true } }
                ToolbarItem(placement: .topBarLeading) { Button("Home") { dismiss() } }
                ToolbarItem(placement: .secondaryAction) {
                    Menu("Backups", systemImage: "externaldrive") {
                        Button("Export Backup") { do { document = TripBackupDocument(data: try store.export()); exporting = true } catch { self.error = error.localizedDescription } }
                        Button("Restore Backup") { importing = true }
                    }
                }
            }
            .sheet(isPresented: $create) { TripSetupView() }
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "SplitTab-Backup") { result in
                if case .failure(let failure) = result { error = failure.localizedDescription }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    let trips = try TripBackup.decode(data)
                    restoreDescription = "Replace all \(store.trips.count) current trips with \(trips.count) trips from this backup? This does not merge. Export a backup first if you want to keep your current records."
                    pendingBackup = data
                } catch { self.error = error.localizedDescription }
            }
            .alert("Replace all trips?", isPresented: Binding(get: { pendingBackup != nil }, set: { if !$0 { pendingBackup = nil } })) {
                Button("Replace All Trips", role: .destructive) {
                    if let data = pendingBackup { do { try store.restore(data) } catch { self.error = error.localizedDescription } }
                    pendingBackup = nil
                }
                Button("Cancel", role: .cancel) { pendingBackup = nil }
            } message: { Text(restoreDescription) }
            .alert("Delete trip?", isPresented: Binding(get: { deletingTrip != nil }, set: { if !$0 { deletingTrip = nil } })) {
                Button("Delete Trip", role: .destructive) {
                    guard let trip = deletingTrip else { return }
                    do {
                        try store.delete(trip.id)
                        if recentTripID == trip.id.uuidString { recentTripID = "" }
                    } catch { self.error = error.localizedDescription }
                    deletingTrip = nil
                }
                Button("Cancel", role: .cancel) { deletingTrip = nil }
            } message: {
                Text("Remove “\(deletingTrip?.name ?? "this trip")” from your trips? Receipts and before/after records remain in History. Live balances will be removed.")
            }
            .tripError($error)
        }
    }
}

struct TripSetupView: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var currency = "USD"
    @State private var people = [TripParticipant(name: "You"), TripParticipant(name: "")]
    @State private var me: UUID?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Trip") { TextField("Trip name", text: $name); Picker("Currency", selection: $currency) { ForEach(TripCurrency.codes, id: \.self) { Text($0).tag($0) } } }
                Section("Participants · tap the circle to identify yourself") {
                    ForEach($people) { $person in
                        HStack {
                            Button { me = person.id } label: { Image(systemName: (me ?? people.first?.id) == person.id ? "person.crop.circle.fill.badge.checkmark" : "circle") }.buttonStyle(.borderless)
                            TextField("Name", text: $person.name)
                        }
                    }
                    Button("Add Participant") { people.append(TripParticipant(name: "")) }
                }
                Text("Choose the currency for combined balances. Each expense and payment can use its own currency and saved rate. Currency locks after the first record.").font(.footnote).foregroundStyle(.secondary)
            }
            .tripStyle().navigationTitle("New Trip")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Create") {
                    do {
                        let trip = TripRecord(name: name.trimmingCharacters(in: .whitespacesAndNewlines), currency: currency, participants: people, me: me ?? people[0].id)
                        try store.save(trip); dismiss()
                    } catch { self.error = error.localizedDescription }
                } }
            }.tripError($error)
        }
    }
}

func tripPosition(_ balance: Int64, trip: TripRecord, me: Bool = false) -> String {
    if balance == 0 { return me ? "You're settled" : "Settled" }
    if balance > 0 { return (me ? "You're owed " : "Gets back ") + trip.money(balance) }
    return (me ? "You owe " : "Owes ") + trip.money(-balance)
}

struct TripDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var deleting = false
    @AppStorage("recentTripID") private var recentTripID = ""
    @Environment(TripStore.self) private var store
    let tripID: UUID
    @State private var expense: TripExpense?
    @State private var payment: TripPayment?
    @State private var settlements = false
    @State private var expandedPaymentDays: Set<Date> = []
    @State private var deletingExpense: TripExpense?
    @State private var deletingPayment: TripPayment?
    @State private var ending = false
    @State private var error: String?
    private var trip: TripRecord? { store.trips.first { $0.id == tripID } }
    var body: some View {
        Group {
            if let trip {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(tripPosition(trip.balances[trip.me] ?? 0, trip: trip, me: true)).font(.title2.bold()).foregroundStyle(Color.splitAccent)
                            Text("Net trip balance · \(trip.currency)").font(.caption).foregroundStyle(.secondary)
                            Text("Spending: \(trip.money(trip.expenses.reduce(0) { $0 + $1.balanceAmount }))")
                        }.padding(.vertical, 8)
                        Button("Add Expense", systemImage: "plus.circle.fill") { expense = TripExpense(payer: trip.me, participants: trip.participants.map(\.id)) }
                        Button("Record Payment", systemImage: "checkmark.circle") { payment = newPayment(trip) }.tint(Color.splitSky).disabled(trip.participants.count < 2)
                        Button("Settle Up", systemImage: "arrow.left.arrow.right") { settlements = true }.tint(Color.splitViolet)
                        NavigationLink("Receipts & history", destination: ArchiveLibraryView(store: store, tripID: trip.id))
                    }
                    Section("Participant balances") {
                        ForEach(trip.participants) { person in
                            NavigationLink { TripParticipantView(tripID: trip.id, personID: person.id) } label: {
                                let balance = trip.balances[person.id] ?? 0
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(person.name).font(.system(.body, design: .rounded, weight: .semibold))
                                        if person.id == trip.me { Text("You").font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text(balance == 0 ? "Settled" : trip.money(abs(balance)))
                                            .font(.system(.subheadline, design: .rounded, weight: .semibold)).monospacedDigit()
                                            .foregroundStyle(balance > 0 ? Color.splitSky : (balance < 0 ? Color.splitCoral : Color.secondary))
                                        if balance != 0 { Text(balance > 0 ? "Gets back" : "Owes").font(.caption).foregroundStyle(.secondary) }
                                    }
                                }.padding(.vertical, 5)
                            }
                        }
                    }
                    Section("Expenses") {
                        if trip.expenses.isEmpty { Text("No expenses yet").foregroundStyle(.secondary) }
                        ForEach(trip.expenses.sorted { $0.createdAt > $1.createdAt }) { item in
                            Button { expense = item } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack { Text(item.title); Spacer(); Text(TripCurrency.format(item.amount, item.fx?.currency ?? trip.currency)) }
                                    Text("Paid by \(trip.person(item.payer))").font(.caption).foregroundStyle(.secondary)
                                }.foregroundStyle(.primary)
                            }
                            .swipeActions(allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) { deletingExpense = item }.tint(.red)
                            }
                        }
                    }
                    Section("Recorded payments") {
                        if trip.payments.isEmpty { Text("No confirmed payments recorded").foregroundStyle(.secondary) }
                        let groupedPayments = Dictionary(grouping: trip.payments) { Calendar.current.startOfDay(for: $0.createdAt) }
                        ForEach(groupedPayments.keys.sorted(by: >), id: \.self) { day in
                            let dayPayments = groupedPayments[day] ?? []
                            DisclosureGroup(isExpanded: Binding(get: {
                                expandedPaymentDays.contains(day)
                            }, set: { expanded in
                                if expanded { expandedPaymentDays.insert(day) }
                                else { expandedPaymentDays.remove(day) }
                            })) {
                                ForEach(dayPayments.sorted { $0.createdAt > $1.createdAt }) { item in
                                    Button { payment = item } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("\(trip.person(item.sender)) → \(trip.person(item.recipient)): \(TripCurrency.format(item.amount, item.fx?.currency ?? trip.currency))")
                                            if let fx = item.fx, fx.currency != trip.currency { Text("\(fx.direction) · \(trip.money(item.balanceAmount)) applied").font(.caption).foregroundStyle(.secondary) }
                                            Text(item.note.isEmpty ? item.createdAt.formatted(date: .omitted, time: .shortened) : item.note).font(.caption).foregroundStyle(.secondary)
                                        }.foregroundStyle(.primary)
                                    }
                                    .swipeActions(allowsFullSwipe: false) {
                                        Button("Delete", role: .destructive) { deletingPayment = item }.tint(.red)
                                    }
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(day.formatted(date: .abbreviated, time: .omitted))
                                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                        Text("\(dayPayments.count) payment\(dayPayments.count == 1 ? "" : "s")")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(trip.money(dayPayments.reduce(0) { $0 + $1.balanceAmount }))
                                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                        .foregroundStyle(Color.splitSky).monospacedDigit()
                                }.padding(.vertical, 4)
                            }
                            .tint(Color.splitSky)
                        }
                    }
                    Section {
                        if trip.status == .active { Button("End Trip") { ending = true } }
                        else {
                            Text(trip.status == .archived ? "Archived · everyone is settled" : "Ended · outstanding balances preserved")
                            Button("Reopen Trip") { var changed = trip; changed.status = .active; persist(changed) }
                        }
                        Button("Delete Trip", role: .destructive) { deleting = true }
                    }
                }.tripStyle().navigationTitle(trip.name).onAppear { recentTripID = trip.id.uuidString }
                .fullScreenCover(item: $expense) { TripExpenseEditor(tripID: trip.id, expense: $0) }
                .sheet(item: $payment) { TripPaymentEditor(tripID: trip.id, payment: $0) }
                .sheet(isPresented: $settlements) { TripSettlementView(tripID: trip.id) }
                .alert("Delete expense?", isPresented: Binding(get: { deletingExpense != nil }, set: { if !$0 { deletingExpense = nil } })) {
                    Button("Delete Expense", role: .destructive) {
                        guard let item = deletingExpense else { return }
                        var changed = trip; changed.expenses.removeAll { $0.id == item.id }; changed.normalizeStatus(); persist(changed)
                        deletingExpense = nil
                    }
                    Button("Cancel", role: .cancel) { deletingExpense = nil }
                } message: { Text("Balances will be recalculated. Recorded payments stay in history.") }
                .alert("Delete payment?", isPresented: Binding(get: { deletingPayment != nil }, set: { if !$0 { deletingPayment = nil } })) {
                    Button("Delete Payment", role: .destructive) {
                        guard let item = deletingPayment else { return }
                        var changed = trip; changed.payments.removeAll { $0.id == item.id }; changed.normalizeStatus(); persist(changed)
                        deletingPayment = nil
                    }
                    Button("Cancel", role: .cancel) { deletingPayment = nil }
                } message: { Text("This undoes the recorded payment and recalculates balances.") }
                .alert("Delete “\(trip.name)”?", isPresented: $deleting) {
                    Button("Delete Trip", role: .destructive) {
                        do {
                            try store.delete(trip.id)
                            if recentTripID == trip.id.uuidString { recentTripID = "" }
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This removes the live trip and balances. Original receipts and before/after records remain in History.")
                }
                .confirmationDialog("End this trip? Outstanding balances and all records will be preserved. Settled trips are archived.", isPresented: $ending, titleVisibility: .visible) {
                    Button("End Trip") { var changed = trip; changed.status = changed.settled ? .archived : .ended; persist(changed) }
                }
            } else { ContentUnavailableView("Trip no longer available", systemImage: "suitcase") }
        }.tripError($error)
    }
    private func persist(_ trip: TripRecord) { do { try store.save(trip) } catch { self.error = error.localizedDescription } }
    private func newPayment(_ trip: TripRecord) -> TripPayment { TripPayment(sender: trip.participants.first { $0.id != trip.me }!.id, recipient: trip.me, amount: 0) }
}

struct TripParticipantsEditor: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let tripID: UUID
    @State private var name = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                if let trip = store.trips.first(where: { $0.id == tripID }) {
                    Section("Currency") {
                        Picker("Combined balances in", selection: Binding(get: { trip.currency }, set: { code in var changed = trip; changed.currency = code; save(changed) })) {
                            ForEach(TripCurrency.codes, id: \.self) { Text($0).tag($0) }
                        }.disabled(trip.currencyLocked)
                        Text(trip.currencyLocked ? "Locked after the first expense or payment. Create another trip to use a different currency." : "Each expense or payment can use any supported currency.").font(.caption)
                    }
                    Section("Identify yourself") {
                        ForEach(trip.participants) { person in
                            Button { var changed = trip; changed.me = person.id; save(changed) } label: {
                                HStack { Text(person.name); Spacer(); if trip.me == person.id { Image(systemName: "checkmark") } }
                            }
                        }
                    }
                    Section("Add someone") {
                        TextField("Participant name", text: $name)
                        Button("Add Participant") {
                            var changed = trip
                            changed.participants.append(TripParticipant(name: name.trimmingCharacters(in: .whitespacesAndNewlines)))
                            if save(changed) { name = "" }
                        }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Text("Existing expenses keep their original participants and shares. Historical participants are retained permanently.").font(.footnote)
                }
            }.tripStyle().navigationTitle("Participants")
            .toolbar { Button("Done") { dismiss() } }.tripError($error)
        }
    }
    @discardableResult private func save(_ trip: TripRecord) -> Bool { do { try store.save(trip); return true } catch { self.error = error.localizedDescription; return false } }
}

struct TripParticipantView: View {
    @Environment(TripStore.self) private var store
    let tripID: UUID
    let personID: UUID
    var body: some View {
        if let t = store.trips.first(where: { $0.id == tripID }) {
            List {
                Section {
                    Text(tripPosition(t.balances[personID] ?? 0, trip: t)).font(.title2.bold())
                }
                Section("Expenses") {
                    ForEach(t.expenses.filter { $0.payer == personID || $0.participants.contains(personID) }) { e in
                        VStack(alignment: .leading) {
                            Text(e.title).font(.headline)
                            if let fx = e.fx, fx.currency != t.currency { Text("Original: \(TripCurrency.format(e.amount, fx.currency)) · \(fx.direction)").font(.caption).foregroundStyle(.secondary) }
                            if e.payer == personID { LabeledContent("Paid for the group", value: t.money(e.balanceAmount)) }
                            LabeledContent("Personal cost", value: t.money(e.balanceShares[personID] ?? 0))
                        }
                    }
                }
                Section("Payments") {
                    ForEach(t.payments.filter { $0.sender == personID || $0.recipient == personID }) { p in
                        Text("\(p.sender == personID ? "Sent to " + t.person(p.recipient) : "Received from " + t.person(p.sender)): \(t.money(p.balanceAmount))")
                    }
                }
            }.tripStyle().navigationTitle(t.person(personID))
        }
    }
}

struct TripSettlementView: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let tripID: UUID
    @State private var toast: String?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                if let trip = store.trips.first(where: { $0.id == tripID }) {
                    let transfers = TripMath.settlements(trip)
                    LazyVStack(spacing: 20) {
                        Text("Current unpaid balances").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                        if let baseline = trip.settlementBaseline {
                            Text("Previously settled through \(baseline.date.formatted(date: .abbreviated, time: .shortened)). Old receipts stay in history; later corrections still count.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if !transfers.isEmpty {
                            HStack(spacing: 20) {
                                Button("Copy totals", systemImage: "doc.on.doc") { copy(trip, breakdown: false) }
                                    .accessibilityIdentifier("settlement.copy.all.totals")
                                Button("Copy breakdown", systemImage: "list.bullet.clipboard") { copy(trip, breakdown: true) }
                                    .accessibilityIdentifier("settlement.copy.all.breakdown")
                                Spacer(minLength: 0)
                            }
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .buttonStyle(.plain).foregroundStyle(Color.splitAccent)
                            .padding(.vertical, 6)
                        }
                        if transfers.isEmpty {
                            ContentUnavailableView("Everyone is settled", systemImage: "checkmark.circle", description: Text("No repayments left."))
                        }
                        ForEach(trip.participants) { recipient in
                            let incoming = transfers.filter { $0.recipient == recipient.id }
                            if !incoming.isEmpty {
                                recipientCard(trip, recipient: recipient, incoming: incoming)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
            }
            .background(Color.splitBg)
            .navigationTitle("Settle Up")
            .toolbar { Button("Done") { dismiss() } }
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast).font(.caption.weight(.semibold))
                        .padding(12).background(.regularMaterial, in: Capsule()).padding()
                        .task(id: toast) {
                            do { try await Task.sleep(for: .seconds(2)) } catch { return }
                            self.toast = nil
                        }
                }
            }
            .tripError($error)
        }
    }

    private func copy(_ trip: TripRecord, sender: UUID? = nil, breakdown: Bool) {
        do {
            try ShareClipboard.copy(TripMath.settlementText(trip, sender: sender, breakdown: breakdown))
            toast = "Copied to clipboard"
        } catch { self.error = error.localizedDescription }
    }

    private func recordPayment(_ transfer: TripTransfer) {
        guard var trip = store.trips.first(where: { $0.id == tripID }) else { return }
        // Recheck the latest balance so a repeated tap cannot record it twice.
        guard TripMath.settlements(trip).contains(where: {
            $0.sender == transfer.sender && $0.recipient == transfer.recipient && $0.amount == transfer.amount
        }) else { return }
        do {
            var payment = TripPayment(sender: transfer.sender, recipient: transfer.recipient, amount: transfer.amount)
            payment.fx = try TripFX.make(amount: transfer.amount, currency: trip.currency, reporting: trip.currency, rate: 1)
            trip.save(payment)
            try store.save(trip)
            toast = "Payment recorded"
        } catch { self.error = error.localizedDescription }
    }

    private func recipientCard(_ trip: TripRecord, recipient: TripParticipant, incoming: [TripTransfer]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(recipient.name)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Receives \(trip.money(incoming.reduce(0) { $0 + $1.amount }))")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.splitSky)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.splitSky.opacity(0.06))

            VStack(spacing: 0) {
                ForEach(incoming) { transfer in
                    if transfer.id != incoming.first?.id {
                        Divider().overlay(Color.splitBorder)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        DisclosureGroup {
                            VStack(spacing: 8) {
                                ForEach(Array(TripMath.settlementBreakdown(trip, transfer: transfer).enumerated()), id: \.offset) { _, line in
                                    HStack(alignment: .top, spacing: 16) {
                                        Text(line.amount < 0 ? "Subtract: " + line.label : line.label).frame(maxWidth: .infinity, alignment: .leading)
                                        Text(trip.money(line.amount)).monospacedDigit().fixedSize(horizontal: true, vertical: false)
                                    }
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 10)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(trip.person(transfer.sender))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(trip.money(transfer.amount)).monospacedDigit()
                            }
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(.vertical, 6)
                        }
                        .tint(.secondary)
                        .accessibilityIdentifier("settlement.breakdown." + trip.person(transfer.sender) + "." + recipient.name)

                        HStack {
                            Menu {
                                Button("Copy totals") { copy(trip, sender: transfer.sender, breakdown: false) }
                                    .accessibilityIdentifier("settlement.copy.person.totals")
                                Button("Copy breakdown") { copy(trip, sender: transfer.sender, breakdown: true) }
                                    .accessibilityIdentifier("settlement.copy.person.breakdown")
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .font(.system(.caption, design: .rounded, weight: .semibold))
                                    .frame(minHeight: 44)
                            }
                            .accessibilityLabel("Copy repayments for " + trip.person(transfer.sender))
                            Spacer()
                            Button {
                                recordPayment(transfer)
                            } label: {
                                Label("Record Payment", systemImage: "checkmark")
                                    .font(.system(.caption, design: .rounded, weight: .semibold))
                                    .foregroundStyle(Color.splitSky)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Color.splitSky.opacity(0.09), in: Capsule())
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Record payment from \(trip.person(transfer.sender)) to \(recipient.name)")
                        }
                    }.padding(.vertical, 10)
                }
            }.padding(.horizontal, 18)
        }
        .background(Color.splitCard)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.splitBorder, lineWidth: 1))
    }
}

extension View {
    func tripStyle() -> some View { scrollContentBackground(.hidden).background(Color.splitBg).keyboardDismissButton() }
    func tripError(_ error: Binding<String?>) -> some View {
        alert("Couldn't complete the action", isPresented: Binding(get: { error.wrappedValue != nil }, set: { if !$0 { error.wrappedValue = nil } })) {
            Button("OK") { error.wrappedValue = nil }
        } message: { Text(error.wrappedValue ?? "") }
    }
}
