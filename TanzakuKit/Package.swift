// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "TanzakuKit",
  // SwiftData と NLContextualEmbedding の両方が使える最低の版 (documents/DIRECTION.md「決めたこと」)。
  platforms: [.macOS(.v14), .iOS(.v17)],
  products: [
    .library(name: "TanzakuKit", targets: ["TanzakuKit"])
  ],
  targets: [
    .target(name: "TanzakuKit"),
    .testTarget(name: "TanzakuKitTests", dependencies: ["TanzakuKit"]),
  ]
)
