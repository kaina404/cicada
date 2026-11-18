// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cicada",
    platforms: [.macOS("14.4")],
    dependencies: [
        // Walkthrough cards draw Mermaid flowcharts and sequence diagrams natively (no WebView).
        .package(url: "https://github.com/2389-research/MermaidKit.git", exact: "2.10.2"),
    ],
    targets: [
        .executableTarget(name: "Cicada", dependencies: ["CicadaWatchControl", .product(name: "MermaidRender", package: "MermaidKit")], path: "Sources/Cicada"),
        .target(name: "CicadaWatchControl", path: "watch",
                exclude: ["App", "Config", "Tests", "scripts", "CicadaWatch.xcodeproj", "README.md", "AGENTS.md", ".gitignore"],
                sources: ["Mac", "Shared"]),
        .testTarget(name: "CicadaWatchControlTests", dependencies: ["CicadaWatchControl"], path: "watch/Tests", exclude: ["Standalone"]),
        .executableTarget(name: "CicadaIcon", path: "Sources/CicadaIcon"),
        .testTarget(name: "CicadaTests", dependencies: ["Cicada"], path: "Tests/CicadaTests"),
    ],
    swiftLanguageModes: [.v5]
)
