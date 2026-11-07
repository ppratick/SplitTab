import SwiftUI
import UniformTypeIdentifiers

struct ArchiveLibraryView: View {
    @Bindable var store: TripStore
    var tripID: UUID? = nil
    var receiptID: UUID? = nil
    @State private var selection = 0
    @State private var exporting = false
    @State private var document: TripBackupDocument?
    @State private var error: String?

    private var relatedReceipts: Set<UUID> {
        guard let tripID else { return [] }
        var ids = Set(store.activity.filter { $0.tripID == tripID }.compactMap(\.receiptID))
        for entry in store.activity where entry.tripID == tripID {
            for data in [entry.before, entry.after].compactMap({ $0 }) {
                if let trip = try? JSONDecoder().decode(TripRecord.self, from: data) {
                    ids.formUnion(trip.expenses.compactMap { $0.receipt?.archiveID })
                }
            }
        }
        return ids
    }
    private var entries: [ActivityRecord] {
        let related = relatedReceipts
        return store.activity.filter {
            if let receiptID { return $0.receiptID == receiptID }
            if let tripID { return $0.tripID == tripID || $0.receiptID.map { related.contains($0) } == true }
            return true
        }.sorted { $0.date > $1.date }
    }
    var body: some View {
        List {
            Section {
                Picker("Show", selection: $selection) {
                    Text("Receipts").tag(0)
                    Text("History").tag(1)
                }.pickerStyle(.segmented)
                Text("Original photos and history stay here when expenses or trips are deleted. Include them in a backup to keep a copy outside this device.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if selection == 0 {
                let receipts = entries.filter { $0.kind == "receipt.captured" }
                if receipts.isEmpty {
                    Text("No saved receipt photos yet. New scans are saved automatically; previously deleted photos cannot be recovered.")
                        .foregroundStyle(.secondary)
                }
                ForEach(receipts) { entry in
                    NavigationLink { ArchivedReceiptView(store: store, receipt: entry) } label: {
                        HStack {
                            if let data = entry.image, let image = UIImage(data: data) {
                                Image(uiImage: image).resizable().scaledToFit().frame(width: 46, height: 64)
                            }
                            VStack(alignment: .leading, spacing: 5) {
                                Text(receiptTitle(entry))
                                Text(entry.date.formatted()).font(.caption).foregroundStyle(.secondary)
                                Text(receiptStatus(entry)).font(.caption).foregroundStyle(Color.splitAccent)
                            }
                        }
                    }
                }
            } else {
                if entries.isEmpty { Text("No recorded activity yet.").foregroundStyle(.secondary) }
                ForEach(entries) { entry in
                    NavigationLink { ArchiveEventView(entry: entry) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.title)
                            Text(entry.date.formatted()).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .tripStyle().navigationTitle("Receipts & history")
        .toolbar {
            Button("Export backup", systemImage: "square.and.arrow.up") {
                do { document = TripBackupDocument(data: try store.export()); exporting = true }
                catch { self.error = error.localizedDescription }
            }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "SplitTab-Backup") {
            if case .failure(let failure) = $0 { error = failure.localizedDescription }
        }
        .tripError($error)
    }
    private func receiptTitle(_ entry: ActivityRecord) -> String {
        store.activity.last { $0.receiptID == entry.receiptID && $0.kind == "receipt.scanned" }?.title ?? "Receipt photo"
    }
    private func receiptStatus(_ entry: ActivityRecord) -> String {
        if store.trips.contains(where: { trip in trip.expenses.contains { $0.receipt?.archiveID == entry.receiptID } }) { return "Saved with expense" }
        if entries.contains(where: { $0.receiptID == entry.receiptID && $0.kind == "receipt.scanned" }) { return "Scanned · original preserved" }
        if entries.contains(where: { $0.receiptID == entry.receiptID && $0.kind == "receipt.failed" }) { return "Scan failed · photo preserved" }
        return "Photo preserved · scan not completed"
    }
}

private struct ArchivedReceiptView: View {
    let store: TripStore
    let receipt: ActivityRecord
    var body: some View {
        List {
            Section("Original photo") {
                if let data = receipt.image, let image = UIImage(data: data) {
                    NavigationLink {
                        ScrollView([.horizontal, .vertical]) {
                            Image(uiImage: image).resizable().scaledToFit()
                                .frame(width: max(600, image.size.width), height: max(800, image.size.height))
                        }.navigationTitle("Original receipt")
                    } label: {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 360)
                    }
                    ShareLink("Share original photo", item: Image(uiImage: image), preview: SharePreview("Receipt", image: Image(uiImage: image)))
                }
                LabeledContent("Saved", value: receipt.date.formatted())
            }
            Section("Scans and corrections") {
                ForEach(store.activity.filter { $0.receiptID == receipt.receiptID }.sorted { $0.date > $1.date }) { entry in
                    NavigationLink { ArchiveEventView(entry: entry) } label: {
                        VStack(alignment: .leading) {
                            Text(entry.title)
                            Text(entry.date.formatted()).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Linked expense history") {
                ForEach(linked) { entry in
                    NavigationLink(entry.title) { ArchiveEventView(entry: entry) }
                }
                if linked.isEmpty { Text("Not added to a trip expense.").foregroundStyle(.secondary) }
            }
        }.tripStyle().navigationTitle("Saved receipt")
    }
    private var linked: [ActivityRecord] {
        store.activity.filter { entry in
            [entry.before, entry.after].compactMap { $0 }.contains { data in
                guard let trip = try? JSONDecoder().decode(TripRecord.self, from: data) else { return false }
                return trip.expenses.contains { $0.receipt?.archiveID == receipt.receiptID }
            }
        }.sorted { $0.date > $1.date }
    }
}

private struct ArchiveEventView: View {
    let entry: ActivityRecord
    var body: some View {
        List {
            Section {
                Text(entry.title).font(.headline)
                Text(entry.date.formatted()).foregroundStyle(.secondary)
            }
            if let image = entry.image.flatMap(UIImage.init(data:)) {
                Section("Preserved image") { Image(uiImage: image).resizable().scaledToFit() }
            }
            if let data = entry.before { Section("Before") { Text(snapshotText(data)).textSelection(.enabled) } }
            if let data = entry.after { Section("After") { Text(snapshotText(data)).textSelection(.enabled) } }
        }.tripStyle().navigationTitle("Activity details")
    }
}

private func snapshotText(_ data: Data) -> String {
    let decoder = JSONDecoder()
    if let trip = try? decoder.decode(TripRecord.self, from: data) { return TripMath.summary(trip) }
    if let bill = try? decoder.decode(BillActivitySnapshot.self, from: data) {
        var lines = ["Currency: " + bill.currency, "Split: " + bill.split,
                     "Fees: " + bill.fees, "Discounts: " + bill.discounts,
                     "People: " + bill.people.map(\.name).joined(separator: ", ")]
        if let receipt = bill.receipt {
            lines += ["", receiptText(receipt)]
            for item in receipt.items {
                let names = bill.people.filter { bill.assignments[item.id]?.contains($0.id) == true }.map(\.name)
                lines.append(item.name + " → " + (names.isEmpty ? "Unassigned" : names.joined(separator: ", ")))
            }
        }
        if let result = bill.result { lines += ["", result] }
        return lines.joined(separator: "\n")
    }
    if let receipt = try? decoder.decode(ReceiptData.self, from: data) { return receiptText(receipt) }
    if let object = try? JSONSerialization.jsonObject(with: data),
       let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
       let text = String(data: pretty, encoding: .utf8) { return text }
    return String(data: data, encoding: .utf8) ?? "Snapshot unavailable"
}

private func receiptText(_ receipt: ReceiptData) -> String {
    let currency = receipt.currencyCode ?? "USD"
    var lines = [receipt.merchantName ?? "Receipt"]
    for item in receipt.items + receipt.surcharges + receipt.discounts {
        lines.append(item.name + ": " + TripCurrency.formatDecimal(item.amount, currency))
    }
    if let tax = receipt.includedTax { lines.append("Tax already included: " + TripCurrency.formatDecimal(tax, currency)) }
    lines.append("Total: " + TripCurrency.formatDecimal(receipt.grandTotal, currency))
    if let fx = receipt.conversion { lines.append("Saved rate: 1 \(fx.sourceCurrency) = \(fx.rateLabel) \(fx.targetCurrency)") }
    return lines.joined(separator: "\n")
}
