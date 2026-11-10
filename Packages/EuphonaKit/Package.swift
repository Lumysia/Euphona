// swift-tools-version: 6.2
import PackageDescription

let models = ["EuphonaVAD", "EuphonaF0", "EuphonaECAPA", "EuphonaTimbre", "EuphonaEase", "EuphonaVoiceQuality"]

let package = Package(
    name: "EuphonaKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "EuphonaKit", targets: ["EuphonaKit"]),
    ],
    targets: [
        // Official ONNX Runtime Apple build (iOS, iOS Simulator, macOS). See docs/decisions.md.
        .binaryTarget(
            name: "onnxruntime",
            url: "https://download.onnxruntime.ai/pod-archive-onnxruntime-c-1.30.0.zip",
            checksum: "e6f1670c14406fd9f082bb400ab197a9b0a9646058ca6366e440642e2b54a2ea"
        ),
        // A thin C interface to ONNX Runtime's C++ API for the Swift engine.
        .target(
            name: "CEuphonaApple",
            dependencies: ["onnxruntime"],
            path: "Sources/Apple",
            // ONNX Runtime's static build needs these system frameworks.
            linkerSettings: [
                .linkedFramework("CoreML"),
                .linkedFramework("Foundation"),
                .linkedFramework("Network"),
                .linkedFramework("UIKit", .when(platforms: [.iOS])),
            ]
        ),
        .target(
            name: "EuphonaKit",
            dependencies: ["CEuphonaApple"],
            path: "Sources",
            exclude: ["Apple", "Models/README.md"],
            sources: ["Swift/EuphonaKit"],
            resources: models.map { .copy("Models/\($0).onnx") }
        ),
        .testTarget(
            name: "EuphonaKitTests",
            dependencies: ["EuphonaKit"],
            exclude: ["Fixtures"]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
