import SwiftUI

struct Person: Identifiable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var colorIndex: Int

    var avatarColor: Color {
        Person.palette[colorIndex % Person.palette.count]
    }

    static let palette: [Color] = [
        Color(red: 0.0,  green: 0.78, blue: 1.0),   // Cyan
        Color(red: 1.0,  green: 0.42, blue: 0.42),  // Coral
        Color(red: 0.55, green: 0.90, blue: 0.46),  // Mint
        Color(red: 1.0,  green: 0.75, blue: 0.0),   // Amber
        Color(red: 0.72, green: 0.46, blue: 1.0),   // Lavender
        Color(red: 1.0,  green: 0.50, blue: 0.0),   // Orange
        Color(red: 0.25, green: 0.85, blue: 0.75),  // Teal
        Color(red: 1.0,  green: 0.30, blue: 0.65),  // Pink
    ]

    static func defaultName(index: Int) -> String { "" }
}
