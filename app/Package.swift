// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QwenTranscribe",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "QwenTranscribe", targets: ["QwenTranscribe"])
    ],
    targets: [
        .executableTarget(name: "QwenTranscribe")
    ]
)
