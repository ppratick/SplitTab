import UIKit

struct OpenAIReceiptService {

    private static let prompt = """
    Extract all line items from this receipt. \
    Return ONLY raw JSON with no markdown or backticks: \
    {"items": [{"name": "item name", "price": 0.00}], \
    "fees": [{"name": "fee name", "price": 0.00}], \
    "discounts": [{"name": "discount name", "price": 0.00}], \
    "subtotal": 0.00, "tax": 0.00, "tax_pct": null, "tip": 0.00, "tip_pct": null}. \
    "items" = actual ordered food/drink only. \
    "fees" = any extra charges such as delivery fee, service fee, bag fee, regulatory fee, convenience fee, or similar (use positive prices). \
    "discounts" = any reductions such as coupons, promotions, member discounts, or credits (use positive prices — the app will negate them). \
    If an item has a quantity greater than 1 (e.g. "2 Burger $20.00"), expand it into that many separate entries each with the per-unit price (e.g. two entries of "Burger" at $10.00 each). \
    If the receipt shows a percentage for tax or tip (e.g. "Tax 8.5% $2.16"), include it as tax_pct or tip_pct (just the number, e.g. 8.5). \
    Skip $0.00 modifier lines, subtotal, tax, tip, total, payment, card, \
    and tip suggestion lines like 16%-$16.84. Use English names only.
    """

    /// Send a receipt image to GPT-4o Vision and return structured ReceiptData.
    static func parseReceipt(image: UIImage) async throws -> ReceiptData {
        let resized = resize(image, maxDimension: 1536)
        guard let jpeg = resized.jpegData(compressionQuality: 0.82) else {
            throw ScanError.invalidImage
        }
        let base64 = jpeg.base64EncodedString()

        let body: [String: Any] = [
            "model": "gpt-4o",
            "max_tokens": 1000,
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

        guard let url = URL(string: Constants.openAIEndpoint) else {
            throw ScanError.apiError("Invalid endpoint URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Constants.openAIKey)", forHTTPHeaderField: "Authorization")
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

        guard let jsonData = cleaned.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw ScanError.noTextFound
        }

        // Food items
        var items: [LineItem] = []
        if let rawItems = parsed["items"] as? [[String: Any]] {
            for entry in rawItems {
                guard let name = entry["name"] as? String, !name.isEmpty,
                      let price = doubleValue(from: entry["price"]),
                      price > 0 else { continue }
                items.append(LineItem(name: name, amount: Decimal.roundToTwo(Decimal(price)), category: .food))
            }
        }

        // Fees
        var surcharges: [LineItem] = []
        if let rawFees = parsed["fees"] as? [[String: Any]] {
            for entry in rawFees {
                guard let name = entry["name"] as? String, !name.isEmpty,
                      let price = doubleValue(from: entry["price"]),
                      price > 0 else { continue }
                surcharges.append(LineItem(name: name, amount: Decimal.roundToTwo(Decimal(price)), category: .fee))
            }
        }

        // Tax & tip
        if let tax = doubleValue(from: parsed["tax"]), tax > 0 {
            let pct = doubleValue(from: parsed["tax_pct"]).map { Decimal($0) }
            surcharges.append(LineItem(name: "Tax", amount: Decimal.roundToTwo(Decimal(tax)), category: .tax, sourcePercent: pct))
        }
        if let tip = doubleValue(from: parsed["tip"]), tip > 0 {
            let pct = doubleValue(from: parsed["tip_pct"]).map { Decimal($0) }
            surcharges.append(LineItem(name: "Tip", amount: Decimal.roundToTwo(Decimal(tip)), category: .tip, sourcePercent: pct))
        }

        // Back-compute sourcePercent for any surcharge the AI didn't give a % for
        let foodTotal = items.reduce(Decimal(0)) { $0 + $1.amount }
        if foodTotal > 0 {
            surcharges = surcharges.map { item in
                guard item.sourcePercent == nil else { return item }
                var updated = item
                updated.sourcePercent = Decimal.roundToTwo(item.amount / foodTotal * 100)
                return updated
            }
        }

        // Discounts (API returns positive values; store as negative amounts)
        var discounts: [LineItem] = []
        if let rawDiscounts = parsed["discounts"] as? [[String: Any]] {
            for entry in rawDiscounts {
                guard let name = entry["name"] as? String, !name.isEmpty,
                      let price = doubleValue(from: entry["price"]),
                      price > 0 else { continue }
                discounts.append(LineItem(name: name, amount: -Decimal.roundToTwo(Decimal(price)), category: .discount))
            }
        }

        // Use subtotal + tax + tip as the reference total so the discrepancy banner compares apples-to-apples
        let subtotalD = doubleValue(from: parsed["subtotal"]) ?? 0
        let taxD      = doubleValue(from: parsed["tax"]) ?? 0
        let tipD      = doubleValue(from: parsed["tip"]) ?? 0
        let parsedTotal: Decimal? = subtotalD > 0 ? Decimal(subtotalD + taxD + tipD) : nil

        return ReceiptData(items: items, surcharges: surcharges, discounts: discounts, parsedTotal: parsedTotal)
    }

    /// Safely extract a Double from either a JSON Double or Int value.
    private static func doubleValue(from value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
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
