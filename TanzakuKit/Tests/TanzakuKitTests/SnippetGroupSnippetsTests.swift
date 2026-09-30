import Foundation
import SwiftData
import Testing

@testable import TanzakuKit

/// `filteredSnippetGroupSnippets(query:snippetGroup:modelContext:embedder:)` が、スニペットグループの中だけを出すことを確かめる。
struct SnippetGroupSnippetsTests {
  /// 本文とキーワードを持つスニペットをストアに入れる。
  private func insertSnippet(modelContext: ModelContext, body: String, keyword: String? = nil) -> Snippet {
    let snippet = Snippet(body: body)
    snippet.keyword = keyword
    modelContext.insert(snippet)
    return snippet
  }

  @Test("検索欄が空ならメニューに並べる順で、グループの外のスニペットは出さない", arguments: ["", "  "])
  func emptyQueryReturnsItemsInMenuOrder(query: String) throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let deploySnippet = insertSnippet(modelContext: modelContext, body: "make deploy")
    let releaseSnippet = insertSnippet(modelContext: modelContext, body: "make release")
    _ = insertSnippet(modelContext: modelContext, body: "make outside")
    let snippetGroup = SnippetGroup(name: "")
    try applySnippetGroupEdit(
      snippetGroup: snippetGroup, name: "dummy-group", keyword: "", snippets: [releaseSnippet, deploySnippet], modelContext: modelContext, now: .now
    )

    #expect(
      try filteredSnippetGroupSnippets(query: query, snippetGroup: snippetGroup, modelContext: modelContext, embedder: nil).map(\.id)
        == [releaseSnippet.id, deploySnippet.id]
    )
  }

  @Test("検索欄に入力があれば、文字列の一致と意味検索のどちらもグループの中だけから出す")
  func queryReturnsMatchesWithinGroup() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let keywordMatchedSnippet = insertSnippet(modelContext: modelContext, body: "echo dummy", keyword: "query")
    _ = insertSnippet(modelContext: modelContext, body: "echo outside", keyword: "query-outside")
    let semanticMatchedSnippet = insertSnippet(modelContext: modelContext, body: "near dummy")
    let outsideSemanticSnippets = (0..<4).map { insertSnippet(modelContext: modelContext, body: "outside dummy \($0)") }
    let snippetGroup = SnippetGroup(name: "")
    try applySnippetGroupEdit(
      snippetGroup: snippetGroup, name: "dummy-group", keyword: "", snippets: [keywordMatchedSnippet, semanticMatchedSnippet],
      modelContext: modelContext, now: .now
    )
    // グループの外のスニペットをグループの中のものより意味が近くし、意味検索の件数の上限を埋めても、グループの中のものが出ることを確かめる。
    var vectorsByText: [String: [Float]] = ["query": [1, 0, 0], "near dummy": [1, 0.5, 0]]
    for snippet in outsideSemanticSnippets {
      vectorsByText[snippet.body] = [1, 0.1, 0]
    }
    let embedder = SnippetTextEmbedder(modelIdentifier: "dummy-model") { [vectorsByText] in vectorsByText[$0] ?? [0, 0, 1] }
    try updateSnippetEmbeddings(modelContext: modelContext, embedder: embedder)

    #expect(
      try filteredSnippetGroupSnippets(query: "query", snippetGroup: snippetGroup, modelContext: modelContext, embedder: embedder).map(\.id)
        == [keywordMatchedSnippet.id, semanticMatchedSnippet.id]
    )
  }
}
