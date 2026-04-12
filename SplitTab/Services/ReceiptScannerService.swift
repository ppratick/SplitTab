import UIKit

enum ScanError: LocalizedError {
    case invalidImage
    case noTextFound
    case cameraUnavailable
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage:       return "Could not process the image."
        case .noTextFound:        return "No items found on the receipt."
        case .cameraUnavailable:  return "Camera is not available on this device."
        case .apiError(let msg):  return "Receipt scan failed: \(msg)"
        }
    }
}

struct ReceiptScannerService {
    /// Send image to GPT-4o Vision and return parsed ReceiptData.
    static func scanAndParse(image: UIImage) async throws -> ReceiptData {
        try await OpenAIReceiptService.parseReceipt(image: image)
    }
}
