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
  dependencies: [
    // 本文のシンタックスハイライト (documents/DIRECTION.md「決めたこと」)。版を固定し、同梱する highlight.js の版 (2.3.0 は 11.11.1) を上げる時は、ハイライトの色とコントラストのテストを見直す。
    .package(url: "https://github.com/raspu/Highlightr.git", exact: "2.3.0")
  ],
  targets: [
    .target(
      name: "TanzakuKit",
      dependencies: [.product(name: "Highlightr", package: "Highlightr")],
      // Licenses/ は Highlightr (MIT) と highlight.js (BSD-3-Clause) のライセンス全文。どちらも配布物に著作権表示を含めることを求め、Highlightr のパッケージはどちらの LICENSE もリソースに入れないため、アプリに同梱する。
      resources: [.process("Localizable.xcstrings"), .copy("Licenses")]
    ),
    // highlight.js の読み込みの時間をテストで測るため、テストからも Highlightr を使う。
    .testTarget(name: "TanzakuKitTests", dependencies: ["TanzakuKit", .product(name: "Highlightr", package: "Highlightr")]),
  ]
)
