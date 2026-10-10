import SwiftUI

struct Person: Identifiable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var colorIndex: Int

    var avatarColor: Color {
        Person.palette[colorIndex % Person.palette.count]
    }

    static let palette: [Color] = [
        Color(red: 0.42, green: 0.65, blue: 1.00),  // Blue
        Color(red: 1.00, green: 0.58, blue: 0.54),  // Coral
        Color(red: 0.56, green: 0.78, blue: 0.94),  // Sky
        Color(red: 0.95, green: 0.72, blue: 0.30),  // Amber
        Color(red: 0.72, green: 0.60, blue: 1.00),  // Violet
        Color(red: 0.92, green: 0.56, blue: 0.34),  // Tangerine
        Color(red: 0.40, green: 0.75, blue: 0.82),  // Teal
        Color(red: 0.90, green: 0.42, blue: 0.64),  // Rose
    ]

    static func defaultName(index: Int) -> String { "" }
}
