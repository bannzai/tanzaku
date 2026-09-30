import SwiftData
import Testing

@testable import TanzakuKit

/// `snippetDisplayTitle(snippet:)` と `snippetBodyFirstLine(body:)` が、タイトルが無いスニペットを本文の 1 行目で代えることを確かめる。
struct SnippetDisplayTitleTests {
  /// タイトルと本文を持つスニペットをインメモリのストアに入れる。ほかのテストと同じく、ストアに入れたモデルで確かめる。
  private func insertSnippet(modelContext: ModelContext, body: String, title: String?) -> Snippet {
    let snippet = Snippet(body: body)
    snippet.title = title
    modelContext.insert(snippet)
    return snippet
  }

  @Test("タイトルがあればタイトルを返す")
  func titleIsUsed() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))

    #expect(snippetDisplayTitle(snippet: insertSnippet(modelContext: modelContext, body: "echo dummy", title: "ダミーの挨拶")) == "ダミーの挨拶")
  }

  @Test("タイトルが無い・空白だけの時は本文の最初の空でない行を返す")
  func bodyFirstLineIsUsedWithoutTitle() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))

    #expect(
      snippetDisplayTitle(snippet: insertSnippet(modelContext: modelContext, body: "export API_TOKEN=dummy-token-for-test\ncurl https://api.example.com", title: nil))
        == "export API_TOKEN=dummy-token-for-test"
    )
    #expect(snippetDisplayTitle(snippet: insertSnippet(modelContext: modelContext, body: "\n\n  echo dummy  \nsecond", title: "  ")) == "echo dummy")
  }

  @Test("本文が空白だけなら空文字を返す")
  func blankBodyIsEmpty() {
    #expect(snippetBodyFirstLine(body: " \n\t\n") == "")
  }
}
