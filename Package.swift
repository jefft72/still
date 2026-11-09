// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Still",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "Still", targets: ["Still"]),
    .library(name: "StillCore", targets: ["StillCore"]),
  ],
  targets: [
    .target(name: "StillCore"),
    .executableTarget(name: "Still", dependencies: ["StillCore"]),
    .testTarget(name: "StillCoreTests", dependencies: ["StillCore"]),
    .testTarget(name: "StillTests", dependencies: ["Still", "StillCore"]),
  ],
  swiftLanguageModes: [.v5]
)
