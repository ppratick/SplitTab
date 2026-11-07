import UIKit

struct OpenAIReceiptService {

    private static let prompt = """
    Extract the receipt accurately. Return ONLY raw JSON, no markdown:
    {"merchant_name": null, "currency": null, "items": [{"name": "item", "price": 0.00}],
    "fees": [{"name": "fee", "price": 0.00}], "discounts": [{"name": "discount", "price": 0.00}],
    "subtotal": null, "total": null, "tax": 0.00, "tax_pct": null, "tax_included": null,
    "tip": 0.00, "tip_pct": null, "alternate_totals": [{"currency": "USD", "total": 0.00}]}.
    All item, fee, discount, tax, tip, subtotal and total amounts MUST use the currency of the item prices.
    Identify that currency from printed evidence; use an ISO code or null when unclear. Curaçao receipts may label Caribbean guilders CG, XCG or NAf; use XCG. US$ means USD. A dollar symbol alone is not evidence of USD.
    total is the actual printed amount due in the ITEM currency. Never calculate it from subtotal plus tax. Return null if unreadable.
    alternate_totals includes only printed equivalent totals due in other currencies, not tendered amounts, change, suggested tips or item prices. Never mix an alternate total into the items or fees. Do not invent exchange rates.
    Tax may already be INCLUDED in item prices: if item amounts already add to the printed total due, the separately shown tax is informational. Set tax_included true; do not treat it as an extra fee. Preserve its amount in tax. If unclear, use null.
    fees includes only extra payable charges. Do not list tax again in fees. Discounts use positive amounts; the app negates them.
    For quantity greater than 1, expand into separate entries at the per-unit price. For example, 2 pizzas with line total 65.50 means two items at 32.75, not two at 65.50.
    merchant_name is the printed name, or null. Include tax/tip percentages only when printed, otherwise null.
    Skip zero-price modifiers, payment/card details, alternate currency totals and suggested tips. Use English item names.
    """

    /// Send a receipt image to GPT-6 Luna and return structured ReceiptData.
    @MainActor
    static func parseReceipt(image: UIImage, originalData: Data? = nil, tripID: UUID? = nil) async throws -> ReceiptData {
        guard let store = TripStore.current else { throw TripIssue("Receipt storage is unavailable. Reopen the app before scanning so your receipt can be preserved.") }
        guard let original = originalData ?? image.pngData() else { throw ScanError.invalidImage }
        let id = UUID()
        try store.append(ActivityRecord(kind: "receipt.captured", title: "Receipt saved before scanning", tripID: tripID, receiptID: id, image: original))
        do {
            var receipt = try await requestReceipt(image: image, receiptID: id, tripID: tripID, store: store)
            receipt.archiveID = id
            try store.append(ActivityRecord(kind: "receipt.scanned", title: receipt.merchantName ?? "Receipt scanned", tripID: tripID, receiptID: id, after: try JSONEncoder().encode(receipt)))
            return receipt
        } catch {
            // Preserve the photo even when credentials, network, extraction or saving fail.
            do { try store.append(ActivityRecord(kind: "receipt.failed", title: "Scan failed — original photo preserved", tripID: tripID, receiptID: id)) }
            catch { throw TripIssue("The photo was saved, but scan history could not be updated. \(error.localizedDescription)") }
            throw error
        }
    }

    @MainActor
    private static func requestReceipt(image: UIImage, receiptID: UUID, tripID: UUID?, store: TripStore) async throws -> ReceiptData {
        let apiKey = try ReceiptAPIConfiguration.apiKey()
        guard !apiKey.isEmpty else {
            throw ScanError.apiError("Add your OpenAI API key in SplitTab Home → Settings → Receipt scanning. You can still enter receipt items manually.")
        }
        let resized = resize(image, maxDimension: 1536)
        guard let jpeg = resized.jpegData(compressionQuality: 0.82) else {
            throw ScanError.invalidImage
        }
        try store.append(ActivityRecord(kind: "receipt.sent", title: "Receipt image submitted to AI", tripID: tripID, receiptID: receiptID, image: jpeg))
        let base64 = jpeg.base64EncodedString()

        let body: [String: Any] = [
            "model": "gpt-6-luna",
            "reasoning_effort": "none",
            "max_completion_tokens": 4000,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image_url",
                            "image_url": ["url": "data:image/jpeg;base64,\(base64)"]
                        ],
                        [
                            "type": "text",
                            "text": prompt
                        ]
                    ]
                ]
            ]
        ]

        var request = URLRequest(url: ReceiptAPIConfiguration.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ScanError.apiError("No HTTP response")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ScanError.apiError("HTTP \(http.statusCode): \(body)")
        }

        return try parseResponse(data)
    }

    // MARK: - Private

    private static func parseResponse(_ data: Data) throws -> ReceiptData {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw ScanError.noTextFound
        }

        // Strip any accidental markdown fences
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleaned.data(using: .utf8) else {
            throw ScanError.noTextFound
        }

        return try ReceiptData.extracted(from: jsonData)
    }

    /// Resize image so its longest side is at most `maxDimension` points.
    private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
