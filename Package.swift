// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIBuddy",
    platforms: [.macOS(.v14)],
    products: [.library(name: "BuddyCore", targets: ["BuddyCore"]),
               .executable(name: "AIBuddy", targets: ["AIBuddy"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "BuddyCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "AIBuddy", dependencies: ["BuddyCore"],
                          resources: [.copy("Resources")]),
        .testTarget(name: "BuddyCoreTests", dependencies: ["BuddyCore"])
    ]
)
