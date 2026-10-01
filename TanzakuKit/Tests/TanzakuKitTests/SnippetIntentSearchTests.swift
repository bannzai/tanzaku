import Foundation
import SwiftData
import Testing

@testable import TanzakuKit

/// App Intents の検索 (`snippetIntentSearchResults`) とコピー (`copySnippetBody`) を、クリップボードと埋め込みモデルの資産を使わずに確かめる。
struct SnippetIntentSearchTests {
  /// タイトル・キーワード・本文を持つスニペットをストアに入れる。
  private func insertSnippet(modelContext: ModelContext, body: String, title: String? = nil, keyword: String? = nil) -> Snippet {
    let snippet = Snippet(body: body)
    snippet.title = title
    snippet.keyword = keyword
    modelContext.insert(snippet)
    return snippet
  }

  @Test("文字列の一致の結果の後に意味検索の結果を並べた 1 列を返す")
  func joinsKeywordAndSemanticMatches() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let keywordMatchedSnippet = insertSnippet(modelContext: modelContext, body: "echo dummy", keyword: "query")
    let semanticMatchedSnippet = insertSnippet(modelContext: modelContext, body: "near dummy")
    _ = insertSnippet(modelContext: modelContext, body: "far dummy")
    let vectorsByText: [String: [Float]] = ["query": [1, 0, 0], "near dummy": [1, 0.1, 0], "far dummy": [0, 1, 0]]
    let embedder = SnippetTextEmbedder(modelIdentifier: "dummy-model") { vectorsByText[$0] ?? [0, 0, 1] }
    try updateSnippetEmbeddings(modelContext: modelContext, embedder: embedder)

    let snippets = try snippetIntentSearchResults(query: "query", modelContext: modelContext, embedder: embedder)

    #expect(snippets.map(\.id) == [keywordMatchedSnippet.id, semanticMatchedSnippet.id])
  }

  @Test("埋め込みが無い時は文字列の一致だけを返す")
  func returnsKeywordMatchesWithoutEmbedder() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let exactMatchedSnippet = insertSnippet(modelContext: modelContext, body: "echo dummy", keyword: "env")
    let titleMatchedSnippet = insertSnippet(modelContext: modelContext, body: "echo dummy", title: "env の説明")
    _ = insertSnippet(modelContext: modelContext, body: "echo unrelated", keyword: "other")

    let snippets = try snippetIntentSearchResults(query: "env", modelContext: modelContext, embedder: nil)

    #expect(snippets.map(\.id) == [exactMatchedSnippet.id, titleMatchedSnippet.id])
  }

  @Test("選んだスニペットの本文をクリップボードへ入れ、使った日時を記録して、そのスニペットを返す")
  func copiesSelectedSnippetBody() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let otherSnippet = insertSnippet(modelContext: modelContext, body: "echo other dummy")
    let snippet = insertSnippet(modelContext: modelContext, body: "export API_TOKEN=dummy-token-for-test", keyword: "envkey")
    var pasteboardStrings: [String] = []
    let usedAt = Date(timeIntervalSince1970: 1_000)

    let copiedSnippet = try copySnippetBody(snippetID: snippet.id, modelContext: modelContext, usedAt: usedAt) { pasteboardStrings.append($0) }

    #expect(copiedSnippet.id == snippet.id)
    #expect(pasteboardStrings == ["export API_TOKEN=dummy-token-for-test"])
    #expect(snippet.lastUsedAt == usedAt)
    #expect(otherSnippet.lastUsedAt == nil)
    #expect(try recentlyUsedSnippets(modelContext: modelContext).map(\.id) == [snippet.id])
  }

  @Test("消されたスニペットは snippetNotFound を投げ、クリップボードに何も入れない")
  func throwsWhenSnippetIsMissing() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    _ = insertSnippet(modelContext: modelContext, body: "echo dummy")
    let missingSnippetID = UUID()
    var pasteboardStrings: [String] = []

    #expect(throws: SnippetIntentError.snippetNotFound(snippetID: missingSnippetID)) {
      try copySnippetBody(snippetID: missingSnippetID, modelContext: modelContext, usedAt: Date(timeIntervalSince1970: 1_000)) { pasteboardStrings.append($0) }
    }
    #expect(pasteboardStrings.isEmpty)
  }
}
