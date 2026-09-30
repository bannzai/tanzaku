import Foundation
import Testing

@testable import TanzakuKit

/// 同梱する依存ライブラリのライセンス全文が、TanzakuKit のリソースとしてアプリに入ることを確かめる。
struct LicensesTests {
  @Test("Highlightr と highlight.js のライセンス全文を著作権表示付きで同梱する", arguments: ["Highlightr-LICENSE", "highlight.js-LICENSE"])
  func licenseIsBundled(licenseFileName: String) throws {
    let licenseURL = try #require(Bundle.module.url(forResource: licenseFileName, withExtension: "txt", subdirectory: "Licenses"))

    #expect(try String(contentsOf: licenseURL, encoding: .utf8).contains("Copyright (c)"))
  }
}
