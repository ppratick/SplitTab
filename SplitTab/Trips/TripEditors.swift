import SwiftUI

struct TripExpenseEditor: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let tripID: UUID
    @State var expense: TripExpense
    @State private var amount = ""
    @State private var currency = "USD"
    @State private var rate = ""
    @State private var inputs: [UUID: String] = [:]
    @State private var session = SplitSessionViewModel()
    @State private var receiptEditor = false
    @State private var assignFirst = false
    @State private var useReceipt = false
    @State private var deleteConfirmation = false
    @State private var editConfirmation = false
    @State private var error: String?
    @State private var initialized = false
    @State private var saved = false
    @State private var captured = false
    @State private var manualReceipt = false
    @State private var reviewedReceipt = false
    @State private var choosingEvenParticipants = false
    private var trip: TripRecord? { store.trips.first { $0.id == tripID } }
    private var existing: Bool { trip?.expenses.contains { $0.id == expense.id } == true }
    var body: some View {
        Group {
            if !existing && !captured {
                HomeView(tripName: trip?.name ?? "Trip", initialCurrency: trip?.currency ?? "USD", onBack: { dismiss() }) { receipt, code in
                    currency = code
                    rate = code == trip?.currency ? "1" : ""
                    session.receipt = receipt ?? .empty
                    session.currencyCode = code
                    useReceipt = receipt != nil
                    expense.title = receipt?.merchantName ?? ""
                    initialized = true
                    captured = true
                    reviewedReceipt = receipt != nil
                    manualReceipt = true
                    useReceipt = true
                    prepareReceipt()
                }
            } else if manualReceipt { manualFlow }
            else { editor }
        }
    }
    private var manualFlow: some View {
        TripReceiptFlow(session: session, currency: currency, startWithSetup: reviewedReceipt,
            availablePeople: trip?.participants.enumerated().map { Person(id: $0.element.id, name: $0.element.name, colorIndex: $0.offset) },
            expenseDetails: AnyView(receiptDetails)) {
                expense.mode = session.splitMode == .even ? .equal : .itemized
                expense.participants = session.people.map(\.id)
                expense.fees = session.feeDistribution
                expense.discounts = session.discountDistribution
                try persist()
        }
    }

    private var participantSelection: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Who’s splitting?")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text("Choose the people to include.").foregroundStyle(.secondary)
                    GlassCard {
                        VStack(spacing: 18) {
                            ForEach(trip?.participants ?? []) { person in
                                Toggle(person.name, isOn: Binding(get: { expense.participants.contains(person.id) }, set: { selected in
                                    if selected { expense.participants.append(person.id) }
                                    else {
                                        expense.participants.removeAll { $0 == person.id }
                                        for key in session.assignments.keys { session.assignments[key]?.remove(person.id) }
                                        for key in expense.assignments.keys { expense.assignments[key]?.remove(person.id) }
                                    }
                                    expense.participants = (trip?.participants ?? []).map(\.id).filter { expense.participants.contains($0) }
                                }))
                            }
                        }
                    }
                    Button {
                        choosingEvenParticipants = false
                        if existing { editConfirmation = true } else { save() }
                    } label: {
                        Text("Calculate").font(.system(.body, design: .rounded, weight: .bold))
                            .foregroundStyle(.black).frame(maxWidth: .infinity).padding(18)
                            .background(Color.splitAccent, in: Capsule())
                    }.disabled(expense.participants.isEmpty)
                        .opacity(expense.participants.isEmpty ? 0.4 : 1)
                        .accessibilityIdentifier("expense.people.continue")
                }.padding(24)
            }.tripStyle().navigationTitle("Participants")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { choosingEvenParticipants = false } } }
        }
    }
    private var editor: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                if let trip {
                    ExpenseSection("Expense") {
                        TextField("Expense name, e.g. Taxi", text: $expense.title).accessibilityIdentifier("expense.name")
                        if useReceipt || expense.mode == .itemized {
                            CurrencyRateFields(currency: $currency, rate: $rate, reporting: trip.currency)
                            LabeledContent("Receipt total", value: TripCurrency.formatDecimal(session.receipt?.grandTotal ?? 0, currency))
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Menu {
                                    ForEach(TripCurrency.codes, id: \.self) { code in
                                        Button(code) { currency = code; rate = code == trip.currency ? "1" : "" }
                                    }
                                } label: {
                                    HStack(spacing: 5) { Text(currency); Image(systemName: "chevron.down").font(.caption2) }
                                }.accessibilityIdentifier("record.currency")
                                TextField("Amount", text: $amount).keyboardType(.decimalPad)
                                    .font(.system(.body, design: .rounded)).monospacedDigit()
                            }
                            if currency != trip.currency {
                                CurrencyRateFields(currency: $currency, rate: $rate, reporting: trip.currency, showsPicker: false)
                            }
                        }
                        HStack {
                            Text("Paid by").foregroundStyle(.secondary)
                            Spacer()
                            Picker("Paid by", selection: $expense.payer) { ForEach(trip.participants) { Text($0.name).tag($0.id) } }.labelsHidden()
                        }
                    }
                    ExpenseSection("How do you want to split?") {
                        SplitMethodCards(selection: expense.mode == .equal ? .even : expense.mode == .itemized ? .itemized : nil) {
                            expense.mode = $0 == .even ? .equal : .itemized
                            if $0 == .itemized {
                                useReceipt = true
                                assignFirst = !(session.receipt?.items.isEmpty ?? true)
                                prepareReceipt()
                                receiptEditor = true
                            }
                        }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                        if [.exact, .percentage, .weights].contains(expense.mode) {
                            Text("This expense keeps its previously saved shares. Choose Even split or By items to change them.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if useReceipt || expense.mode == .itemized {
                        ExpenseSection("Receipt") {
                            Button(expense.mode == .itemized ? "Review receipt & assign items" : "Edit receipt", systemImage: "receipt") {
                                assignFirst = false
                                prepareReceipt()
                                receiptEditor = true
                            }.disabled(expense.participants.isEmpty)
                            if expense.mode == .itemized {
                            VStack(alignment: .leading, spacing: 8) {
                                if let receipt = session.receipt, !receipt.surcharges.isEmpty {
                                    Text("Tax, tip & fees").font(.caption).foregroundStyle(.secondary)
                                    FeeToggleBar(selection: $expense.fees)
                                }
                                if let receipt = session.receipt, !receipt.discounts.isEmpty {
                                    Text("Discounts").font(.caption).foregroundStyle(.secondary)
                                    FeeToggleBar(selection: $expense.discounts, accent: .splitViolet)
                                }
                            }
                            Text("Assign each item. Proportional fees and discounts follow the assigned item subtotals.").font(.caption)
                            } else {
                                Button("Use a quick amount instead") {
                                    if let total = session.receipt?.grandTotal, total > 0 {
                                        amount = NSDecimalNumber(decimal: total).stringValue
                                    }
                                    useReceipt = false
                                }
                            }
                        }
                    }
                    if useReceipt || expense.mode == .itemized || !amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ExpenseSection("") {
                        switch preview(trip) {
                        case .success(let result):
                            if currency != trip.currency, let fx = result.fx { LabeledContent("Trip total", value: trip.money(fx.convertedAmount)).foregroundStyle(Color.splitAccent) }
                            ForEach(trip.participants.filter { expense.participants.contains($0.id) }) { person in
                                VStack(alignment: .leading, spacing: 3) {
                                    LabeledContent(person.name, value: TripCurrency.format(result.shares[person.id] ?? 0, currency))
                                    if currency != trip.currency { Text("\(trip.money(result.balanceShares[person.id] ?? 0)) in trip balances").font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        case .failure(let failure): Text(failure.localizedDescription).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    }
                    if existing { ExpenseSection("") { Button("Delete Expense", role: .destructive) { deleteConfirmation = true } } }
                }
            }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively).tripStyle().navigationTitle(existing ? "Edit Expense" : "Add Expense")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(expense.mode == .equal ? "Calculate" : "Save to trip") { if expense.mode == .equal { choosingEvenParticipants = true } else if existing { editConfirmation = true } else { save() } }.disabled(saved) }
            }
            .onAppear {
                guard !initialized, let trip else { return }; initialized = true
                currency = expense.fx?.currency ?? trip.currency
                rate = expense.fx.map { NSDecimalNumber(decimal: $0.rate).stringValue } ?? "1"
                amount = expense.amount == 0 ? "" : NSDecimalNumber(decimal: Decimal(expense.amount) / TripCurrency.factor(currency)).stringValue
                inputs = expense.inputs.mapValues { NSDecimalNumber(decimal: $0).stringValue }
                session.receipt = expense.receipt ?? .empty
                useReceipt = expense.receipt.map { !$0.items.isEmpty || !$0.surcharges.isEmpty || !$0.discounts.isEmpty } ?? false
                session.assignments = expense.assignments
            }
            .sheet(isPresented: $choosingEvenParticipants) { participantSelection }
            .fullScreenCover(isPresented: $receiptEditor, onDismiss: {
                expense.fees = session.feeDistribution
                expense.discounts = session.discountDistribution
                if saved { dismiss() }
            }) {
                TripReceiptFlow(session: session, currency: currency, startWithAssignments: assignFirst, confirmSave: existing,
                    availablePeople: trip?.participants.enumerated().map { Person(id: $0.element.id, name: $0.element.name, colorIndex: $0.offset) },
                    expenseDetails: manualReceipt ? AnyView(receiptDetails) : nil) {
                    expense.mode = session.splitMode == .even ? .equal : .itemized
                    expense.participants = session.people.map(\.id)
                    expense.fees = session.feeDistribution
                    expense.discounts = session.discountDistribution
                    try persist()
                }
            }
            .confirmationDialog("Save changes and recalculate balances? Recorded payments will remain unchanged.", isPresented: $editConfirmation, titleVisibility: .visible) { Button("Save Changes") { save() } }
            .confirmationDialog("Delete this expense? Balances will be recalculated; recorded payments remain in history.", isPresented: $deleteConfirmation, titleVisibility: .visible) {
                Button("Delete Expense", role: .destructive) {
                    guard var trip else { return }
                    trip.expenses.removeAll { $0.id == expense.id }; trip.normalizeStatus()
                    do { try store.save(trip); dismiss() } catch { self.error = error.localizedDescription }
                }
            }.tripError($error)
        }
    }
    private var receiptDetails: some View {
        ExpenseSection("Expense") {
            TextField("Expense name", text: $expense.title).accessibilityIdentifier("expense.name")
            if let trip {
                HStack {
                    Text("Paid by").foregroundStyle(.secondary)
                    Spacer()
                    Picker("Paid by", selection: $expense.payer) {
                        ForEach(trip.participants) { Text($0.name).tag($0.id) }
                    }.labelsHidden()
                }
                Text(TripCurrency.formatDecimal(session.receipt?.grandTotal ?? 0, currency))
                    .font(.system(.body, design: .rounded, weight: .semibold)).foregroundStyle(Color.splitAccent)
                if currency != trip.currency {
                    CurrencyRateFields(currency: $currency, rate: $rate, reporting: trip.currency, showsPicker: false)
                }
            }
        }
        .onAppear {
            if expense.title.isEmpty { expense.title = session.receipt?.merchantName ?? session.receipt?.items.first?.name ?? "Expense" }
        }
    }

    private func prepareReceipt() {
        guard let trip else { return }
        session.people = trip.participants.enumerated().map { Person(id: $0.element.id, name: $0.element.name, colorIndex: $0.offset) }
        session.splitMode = expense.mode == .itemized ? .itemized : .even
        session.feeDistribution = expense.fees
        session.discountDistribution = expense.discounts
    }
    private func preview(_ trip: TripRecord) -> Result<TripExpense, Error> {
        Result {
            var e = expense
            e.receipt = useReceipt || e.mode == .itemized ? session.receipt : nil
            e.assignments = session.assignments
            if let receipt = e.receipt {
                for line in receipt.items + receipt.surcharges + receipt.discounts { _ = try TripCurrency.minor(line.amount, currency) }
            }
            e.amount = try TripCurrency.minor((useReceipt || e.mode == .itemized) ? (session.receipt?.grandTotal ?? 0) : TripCurrency.parse(amount), currency)
            e.inputs = [:]
            if [.exact, .percentage, .weights].contains(e.mode) {
                for id in e.participants { e.inputs[id] = try TripCurrency.parse(inputs[id] ?? (e.mode == .weights ? "1" : "0")) }
            }
            e.shares = try TripMath.shares(e, currency: currency)
            try e.convert(currency: currency, reporting: trip.currency, rate: currency == trip.currency ? 1 : TripCurrency.parse(rate))
            return e
        }
    }
    private func persist() throws {
        guard !saved, var trip else { return }
        let value = try preview(trip).get()
        trip.save(value)
        try store.save(trip)
        saved = true
    }
    private func save() {
        do { try persist(); dismiss() }
        catch { self.error = error.localizedDescription }
    }

}

private struct ExpenseSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.content = content
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !title.isEmpty {
                Text(title).font(.system(.subheadline, design: .rounded, weight: .bold)).foregroundStyle(.secondary)
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 18, content: content)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(.body, design: .rounded))
            }
        }.tint(Color.splitAccent)
    }
}

/// Reuses existing receipt capture, photo parsing, editing and assignment views with
/// trip participant identities. This session never touches standalone bill state.
struct TripReceiptFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: SplitSessionViewModel
    let currency: String
    var startWithAssignments = false
    var startWithSetup = false
    var confirmSave = false
    var availablePeople: [Person]? = nil
    var expenseDetails: AnyView? = nil
    var onSave: () throws -> Void
    @State private var saveError: String?
    @State private var confirmingSave = false
    var body: some View {
        NavigationStack(path: $session.navigationPath) {
            Group {
                if startWithAssignments { ItemAssignmentView(availablePeople: availablePeople) }
                else if startWithSetup { SplitSetupView(availablePeople: availablePeople, expenseDetails: expenseDetails) }
                else { ReceiptReviewView() }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .navigationDestination(for: SplitTabRoute.self) { route in
                switch route {
                case .receiptReview: ReceiptReviewView()
                case .splitSetup:
                    if let availablePeople { SplitSetupView(availablePeople: availablePeople, expenseDetails: expenseDetails) }
                    else if session.splitMode == .itemized { ItemAssignmentView(availablePeople: availablePeople) }
                    else { results }
                case .itemAssignment: ItemAssignmentView(availablePeople: availablePeople)
                case .results: results
                case .scanner: EmptyView()
                }
            }

        }
        .environment(session)
        .environment(\.tripCurrencyCode, currency)
        .onAppear { session.navigationPath = NavigationPath(); session.currencyCode = currency }
        .tripError(Binding(get: { session.calculationError }, set: { session.calculationError = $0 }))
    }
    private var results: some View {
        ResultsView(onSaveToTrip: {
            if confirmSave { confirmingSave = true } else { save() }
        })
        .tripError($saveError)
        .confirmationDialog("Save changes and recalculate balances? Recorded payments will remain unchanged.", isPresented: $confirmingSave, titleVisibility: .visible) {
            Button("Save Changes") { save() }
        }
    }
    private func save() {
        do { try onSave(); dismiss() }
        catch { saveError = error.localizedDescription }
    }

}

struct TripPaymentEditor: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let tripID: UUID
    @State var payment: TripPayment
    @State private var amount = ""
    @State private var currency = "USD"
    @State private var rate = ""
    @State private var error: String?
    @State private var deleting = false
    @State private var initialized = false
    @State private var saved = false
    private var trip: TripRecord? { store.trips.first { $0.id == tripID } }
    private var existing: Bool { trip?.payments.contains { $0.id == payment.id } == true }
    var body: some View {
        NavigationStack {
            Form {
                if let trip {
                    Section("Confirmed payment") {
                        CurrencyRateFields(currency: $currency, rate: $rate, reporting: trip.currency)
                        Picker("From", selection: $payment.sender) { ForEach(trip.participants) { Text($0.name).tag($0.id) } }
                        Picker("To", selection: $payment.recipient) { ForEach(trip.participants) { Text($0.name).tag($0.id) } }
                        TextField("Amount", text: $amount).keyboardType(.decimalPad)
                        TextField("Method or note (optional)", text: $payment.note)
                    }
                    if existing { Button("Undo Payment", role: .destructive) { deleting = true } }
                }
            }.scrollDismissesKeyboard(.interactively).tripStyle().navigationTitle(existing ? "Correct Payment" : "Record Payment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(saved) }
            }
            .onAppear {
                guard !initialized, let trip else { return }; initialized = true
                currency = payment.fx?.currency ?? trip.currency
                rate = payment.fx.map { NSDecimalNumber(decimal: $0.rate).stringValue } ?? "1"
                amount = payment.amount == 0 ? "" : NSDecimalNumber(decimal: Decimal(payment.amount) / TripCurrency.factor(currency)).stringValue
            }
            .confirmationDialog("Undo this recorded payment? Its effect on balances will be reversed.", isPresented: $deleting, titleVisibility: .visible) {
                Button("Undo Payment", role: .destructive) {
                    guard var trip else { return }
                    trip.payments.removeAll { $0.id == payment.id }; trip.normalizeStatus()
                    do { try store.save(trip); dismiss() } catch { self.error = error.localizedDescription }
                }
            }.tripError($error)
        }
    }
    private func paymentConversion(_ trip: TripRecord) throws -> TripFX {
        guard payment.sender != payment.recipient else { throw TripIssue("Choose different participants.") }
        return try TripFX.make(amount: TripCurrency.minor(TripCurrency.parse(amount), currency), currency: currency, reporting: trip.currency, rate: currency == trip.currency ? 1 : TripCurrency.parse(rate))
    }
    private func save() {
        guard !saved, var trip else { return }
        do {
            payment.amount = try TripCurrency.minor(TripCurrency.parse(amount), currency)
            payment.fx = try paymentConversion(trip)
            trip.save(payment); try store.save(trip); saved = true; dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct TripCurrencyKey: EnvironmentKey { static let defaultValue: String? = nil }
extension EnvironmentValues {
    var tripCurrencyCode: String? {
        get { self[TripCurrencyKey.self] }
        set { self[TripCurrencyKey.self] = newValue }
    }
}


struct CurrencyRateFields: View {
    @Binding var currency: String
    @Binding var rate: String
    let reporting: String
    var showsPicker = true
    var showsRate = true
    var body: some View {
        if showsPicker {
        Picker("Currency", selection: Binding(get: { currency }, set: { value in
            if value != currency { currency = value; rate = value == reporting ? "1" : "" }
        })) {
            ForEach(TripCurrency.codes, id: \.self) { Text($0 == "XCG" ? "XCG · Caribbean guilder" : $0).tag($0) }
        }.accessibilityIdentifier("record.currency")
        }
        if showsRate && currency != reporting {
            HStack {
                Text("1 \(currency) =")
                TextField("Rate", text: $rate).keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityIdentifier("record.rate")
                Text(reporting).foregroundStyle(.secondary)
            }
            Text("Enter your exchange rate. This rate is saved with this record and never updates automatically.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

