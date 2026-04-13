import Foundation

struct PersonResult: Identifiable {
    let id: UUID
    let name: String
    let avatarColorIndex: Int
    let assignedItems: [(item: LineItem, shareAmount: Decimal)]
    let itemSubtotal: Decimal
    let feeShare: Decimal
    let discountShare: Decimal
    let total: Decimal
}

struct SplitResult {
    let personResults: [PersonResult]
    let unassignedItems: [LineItem]
    let feeDistribution: FeeDistribution
    let splitMode: SplitMode
}
