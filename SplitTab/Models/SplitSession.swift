import Foundation

enum SplitMode: String, CaseIterable, Identifiable {
    case itemized = "Itemized"
    case even     = "Even Split"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .even:     return "Divide total equally among everyone"
        case .itemized: return "Pay for what each person got"
        }
    }

    var systemImage: String {
        switch self {
        case .even:     return "equal.circle.fill"
        case .itemized: return "list.bullet.clipboard.fill"
        }
    }
}

enum FeeDistribution: String, CaseIterable, Identifiable {
    case proportional = "Proportional"
    case even         = "Even"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .even:         return "Split tax & fees equally"
        case .proportional: return "Based on each person's share"
        }
    }

    var systemImage: String {
        switch self {
        case .even:         return "equal.circle"
        case .proportional: return "chart.pie"
        }
    }
}

// lineItem.id → Set of person.id who had that item
typealias ItemAssignments = [UUID: Set<UUID>]
