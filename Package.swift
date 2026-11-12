// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIBuddy",
    platforms: [.macOS(.v14)],
    products: [.library(name: "BuddyCore", targets: ["BuddyCore"]),
               .executable(name: "BuddyDesktop", targets: ["BuddyDesktop"])],
    dependencies: [.package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.7.3")],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "BuddyCore", dependencies: ["CSQLite", .product(name: "Markdown", package: "swift-markdown")]),
        .executableTarget(name: "BuddyDesktop", dependencies: ["BuddyCore"], path: "Sources/AIBuddy",
                          resources: [.copy("Resources")]),
        .testTarget(name: "BuddyCoreTests", dependencies: ["BuddyCore"])
    ]
)
