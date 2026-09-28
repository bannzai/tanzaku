import Foundation
import Testing

@testable import TanzakuKit

/// `snippetDisplayTitle(snippet:)` のタイトルと本文の 1 行目の出し分けを確かめる。
struct SnippetDisplayTitleTests {
  @Test("タイトルがあればタイトルを出す")
  func titleIsUsed() {
    let snippet = Snippet(body: "echo dummy")
    snippet.title = "Dummy title"

    #expect(snippetDisplayTitle(snippet: snippet) == "Dummy title")
  }

  @Test("タイトルが無いか空白だけなら、本文の空白だけではない最初の行を出す", arguments: [nil, "", "  "] as [String?])
  func firstBodyLineIsUsedWithoutTitle(title: String?) {
    let snippet = Snippet(body: "\n  \nexport API_TOKEN=dummy-token-for-test\necho done")
    snippet.title = title

    #expect(snippetDisplayTitle(snippet: snippet) == "export API_TOKEN=dummy-token-for-test")
  }
}
