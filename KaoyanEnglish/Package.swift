// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "KaoyanEnglish",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "KaoyanCore", targets: ["KaoyanCore"])],
    targets: [
        .target(name: "KaoyanCore", path: "KaoyanEnglish",
                exclude: ["App", "Views", "ViewModels", "Resources"], linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "KaoyanEnglishTests", dependencies: ["KaoyanCore"], path: "KaoyanEnglishTests")
    ]
)
