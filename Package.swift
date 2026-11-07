// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SplitTabTripLogic",
    platforms: [.macOS(.v14)],
    products: [.library(name: "TripCore", targets: ["TripCore"])],
    targets: [
        .target(name: "TripCore", path: "SplitTab", exclude: ["Assets.xcassets", "Constants.swift", "Extensions", "Services", "SplitTabApp.swift", "ViewModels", "Views", "Trips/TripViews.swift", "Trips/TripEditors.swift"], sources: ["Calculators/SplitCalculator.swift", "Models/Person.swift", "Models/SplitResult.swift", "Models/SplitCopyText.swift", "Trips/TripDomain.swift", "Trips/TripStore.swift", "Trips/ActivityArchive.swift", "Models/LineItem.swift", "Models/ReceiptData.swift", "Models/SplitSession.swift"]),
        .testTarget(name: "TripCoreTests", dependencies: ["TripCore"], path: "Tests/TripCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
