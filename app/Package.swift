// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Qwen3ASR",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Qwen3ASR", targets: ["Qwen3ASR"])
    ],
    targets: [
        .executableTarget(name: "Qwen3ASR")
    ]
)
