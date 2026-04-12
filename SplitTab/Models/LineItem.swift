import Foundation

enum LineItemCategory: String, Codable, CaseIterable, Identifiable {
    case food     = "Food"
    case tax      = "Tax"
    case tip      = "Tip"
    case fee      = "Fee"
    case discount = "Discount"
    case unknown  = "Other"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .food:     return "fork.knife"
        case .tax:      return "building.columns"
        case .tip:      return "heart.fill"
        case .fee:      return "plus.circle.fill"
        case .discount: return "tag.fill"
        case .unknown:  return "questionmark.circle"
        }
    }

    var isSurcharge: Bool {
        self == .tax || self == .tip || self == .fee
    }

    /// Default name pre-filled in the Add Item sheet when this category is selected.
    var defaultName: String {
        switch self {
        case .food:     return ""
        case .tax:      return "Tax"
        case .tip:      return "Tip"
        case .fee:      return "Fee"
        case .discount: return "Discount"
        case .unknown:  return "Other"
        }
    }
}

struct LineItem: Identifiable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var amount: Decimal
    var category: LineItemCategory
    var isLowConfidence: Bool = false
    /// Set when the amount was entered as a percentage of the food subtotal.
    var sourcePercent: Decimal? = nil

    var isDiscount: Bool { amount < 0 }
}
