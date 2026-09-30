// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "TanzakuKit",
  // 保存前の検査のエラーの文言を画面に出すため、アプリと同じ開発言語 (英語) を既定にして翻訳を持つ。
  defaultLocalization: "en",
  // SwiftData と NLContextualEmbedding の両方が使える最低の版 (documents/DIRECTION.md「決めたこと」)。
  platforms: [.macOS(.v14), .iOS(.v17)],
  products: [
    .library(name: "TanzakuKit", targets: ["TanzakuKit"])
  ],
  targets: [
    .target(name: "TanzakuKit", resources: [.process("Localizable.xcstrings")]),
    .testTarget(name: "TanzakuKitTests", dependencies: ["TanzakuKit"]),
  ]
)
