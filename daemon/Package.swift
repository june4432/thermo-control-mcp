// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "thermod",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "thermod",
            path: "Sources/thermod"
        )
    ]
)
