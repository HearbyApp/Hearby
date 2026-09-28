// swift-tools-version: 5.9
// Local vendored replacement for https://github.com/willwade/sherpa-onnx-spm
// (sherpa-onnx 1.13.2 artifacts). The upstream package ships two xcframeworks
// whose Headers both contain a module.modulemap, which makes Xcode fail with
// "Multiple commands produce .../include/module.modulemap". Here the two
// static libs are merged (libtool) into one macOS-only xcframework, so there
// is a single Headers dir and no collision. See Vendor/SherpaOnnx/README.md
// for how to regenerate the xcframework.

import PackageDescription

let package = Package(
    name: "SherpaOnnx",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SherpaOnnx",
            targets: ["SherpaOnnx"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "sherpa-onnx",
            path: "Frameworks/sherpa-onnx.xcframework"
        ),
        .target(
            name: "SherpaOnnx",
            dependencies: ["sherpa-onnx"],
            path: "Sources/SherpaOnnx",
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
            ]
        ),
    ]
)
