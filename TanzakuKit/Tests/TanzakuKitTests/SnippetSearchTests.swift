import Foundation
import SwiftData
import Testing

@testable import TanzakuKit

/// `searchSnippets(query:modelContext:embedder:)` の一致の種類と結果の分け方を、埋め込みモデルの資産を使わない偽の埋め込みで確かめる。
struct SnippetSearchTests {
  /// タイトル・キーワード・本文を持つスニペットをストアに入れる。
  private func insertSnippet(modelContext: ModelContext, body: String, title: String? = nil, keyword: String? = nil, updatedAt: Date = .now) -> Snippet {
    let snippet = Snippet(body: body)
    snippet.title = title
    snippet.keyword = keyword
    snippet.updatedAt = updatedAt
    modelContext.insert(snippet)
    return snippet
  }

  /// テキストごとに決めたベクトルを返す偽の埋め込み。決めていないテキストは原点から離れた別の向きにする。
  private func lookupEmbedder(vectorsByText: [String: [Float]]) -> SnippetTextEmbedder {
    SnippetTextEmbedder(modelIdentifier: "dummy-model") { text in
      vectorsByText[text] ?? [0, 0, 1]
    }
  }

  @Test("キーワードの完全一致・前方一致・タイトルと本文の一致を、この順に分けて返す")
  func keywordMatchKinds() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let titleMatchedSnippet = insertSnippet(modelContext: modelContext, body: "echo dummy", title: "dummy env の説明")
    let bodyMatchedSnippet = insertSnippet(modelContext: modelContext, body: "export DUMMY_ENV=dummy-token-for-test")
    let prefixMatchedSnippet = insertSnippet(modelContext: modelContext, body: "echo dummy", keyword: "envkey")
    let exactMatchedSnippet = insertSnippet(modelContext: modelContext, body: "echo dummy", keyword: "env")
    _ = insertSnippet(modelContext: modelContext, body: "echo unrelated", keyword: "other")

    let result = try searchSnippets(query: "env", modelContext: modelContext, embedder: nil)

    #expect(result.keywordMatches.map(\.snippet.id).prefix(2) == [exactMatchedSnippet.id, prefixMatchedSnippet.id])
    #expect(Set(result.keywordMatches.map(\.snippet.id).suffix(2)) == [titleMatchedSnippet.id, bodyMatchedSnippet.id])
    #expect(result.keywordMatches.map(\.kind) == [.keywordExact, .keywordPrefix, .titleOrBody, .titleOrBody])
    #expect(result.semanticMatches.isEmpty)
  }

  @Test("同じ種類の一致は更新日時の新しい順に並べる")
  func sameKindIsOrderedByUpdatedAt() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let olderSnippet = insertSnippet(modelContext: modelContext, body: "dummy older", updatedAt: Date(timeIntervalSince1970: 0))
    let newerSnippet = insertSnippet(modelContext: modelContext, body: "dummy newer", updatedAt: Date(timeIntervalSince1970: 100))

    let result = try searchSnippets(query: "dummy", modelContext: modelContext, embedder: nil)

    #expect(result.keywordMatches.map(\.snippet.id) == [newerSnippet.id, olderSnippet.id])
  }

  @Test("タイトルと本文の一致は大文字と小文字・全角と半角・ひらがなとカタカナを区別せず、空白で区切った語をすべて含むものだけ返す")
  func titleOrBodyMatchIsFuzzy() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let snippet = insertSnippet(modelContext: modelContext, body: "Ｄｏｃｋｅｒ のイメージを消す")
    _ = insertSnippet(modelContext: modelContext, body: "docker ps")

    #expect(try searchSnippets(query: "docker いめーじ", modelContext: modelContext, embedder: nil).keywordMatches.map(\.snippet.id) == [snippet.id])
    #expect(try searchSnippets(query: "DOCKER", modelContext: modelContext, embedder: nil).keywordMatches.count == 2)
    #expect(try searchSnippets(query: "がぞう", modelContext: modelContext, embedder: nil).keywordMatches.isEmpty)
  }

  @Test("空のクエリは何も返さない", arguments: ["", "  \n"])
  func emptyQueryReturnsNothing(query: String) throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    _ = insertSnippet(modelContext: modelContext, body: "echo dummy", keyword: "dummy")

    let result = try searchSnippets(query: query, modelContext: modelContext, embedder: lookupEmbedder(vectorsByText: [:]))

    #expect(result.keywordMatches.isEmpty)
    #expect(result.semanticMatches.isEmpty)
  }

  @Test("意味検索の結果は近い順に並び、文字列で一致したものを除く")
  func semanticMatchesExcludeKeywordMatches() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let nearestSnippet = insertSnippet(modelContext: modelContext, body: "nearest dummy")
    let nearSnippet = insertSnippet(modelContext: modelContext, body: "near dummy")
    let keywordMatchedSnippet = insertSnippet(modelContext: modelContext, body: "dummy", keyword: "query")
    let embedder = lookupEmbedder(vectorsByText: [
      "query": [1, 0, 0],
      "nearest dummy": [1, 0.1, 0],
      "near dummy": [1, 1, 0],
      "query\ndummy": [1, 0, 0],
    ])
    try updateSnippetEmbeddings(modelContext: modelContext, embedder: embedder)

    let result = try searchSnippets(query: "query", modelContext: modelContext, embedder: embedder)

    #expect(result.keywordMatches.map(\.snippet.id) == [keywordMatchedSnippet.id])
    #expect(result.semanticMatches.map(\.id) == [nearestSnippet.id, nearSnippet.id])
  }

  @Test("埋め込みが無い時は意味検索なしで文字列の一致だけを返す")
  func noEmbedderReturnsOnlyKeywordMatches() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let keywordMatchedSnippet = insertSnippet(modelContext: modelContext, body: "echo dummy", keyword: "query")
    _ = insertSnippet(modelContext: modelContext, body: "near dummy")
    try updateSnippetEmbeddings(modelContext: modelContext, embedder: lookupEmbedder(vectorsByText: ["near dummy": [1, 0, 0]]))

    let result = try searchSnippets(query: "query", modelContext: modelContext, embedder: nil)

    #expect(result.keywordMatches.map(\.snippet.id) == [keywordMatchedSnippet.id])
    #expect(result.semanticMatches.isEmpty)
  }

  @Test("埋め込みモデルが違うベクトルと、更新前の本文のベクトルは意味検索に使わない")
  func staleEmbeddingsAreIgnored() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let otherModelSnippet = insertSnippet(modelContext: modelContext, body: "other model dummy")
    let updatedSnippet = insertSnippet(modelContext: modelContext, body: "before update dummy")
    let vectorsByText: [String: [Float]] = ["query": [1, 0, 0], "other model dummy": [1, 0, 0], "before update dummy": [1, 0, 0]]
    try updateSnippetEmbeddings(
      modelContext: modelContext,
      embedder: SnippetTextEmbedder(modelIdentifier: "other-dummy-model") { vectorsByText[$0] ?? [0, 0, 1] }
    )
    let embedder = lookupEmbedder(vectorsByText: vectorsByText)
    modelContext.insert(
      SnippetEmbedding(
        snippetID: updatedSnippet.id,
        modelIdentifier: embedder.modelIdentifier,
        sourceHash: snippetEmbeddingSourceHash(sourceText: "before update dummy"),
        vector: snippetEmbeddingVectorData(vector: [1, 0, 0])
      )
    )
    updatedSnippet.body = "after update dummy"

    let result = try searchSnippets(query: "query", modelContext: modelContext, embedder: embedder)

    #expect(!result.semanticMatches.map(\.id).contains(otherModelSnippet.id))
    #expect(!result.semanticMatches.map(\.id).contains(updatedSnippet.id))
  }

  @Test("意味検索の結果は最大 3 件で、最低の類似度に届かないものは返さない")
  func semanticMatchesAreLimited() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let snippets = (0..<5).map { insertSnippet(modelContext: modelContext, body: "dummy \($0)") }
    let embedder = lookupEmbedder(vectorsByText: [
      "query": [1, 0, 0],
      "dummy 0": [1, 0, 0],
      "dummy 1": [1, 0.2, 0],
      "dummy 2": [1, 0.4, 0],
      "dummy 3": [1, 0.6, 0],
      "dummy 4": [-1, 0, 0],
    ])
    try updateSnippetEmbeddings(modelContext: modelContext, embedder: embedder)

    #expect(
      try semanticSnippetMatches(query: "query", snippets: snippets, modelContext: modelContext, embedder: embedder, limit: 3, minimumSimilarity: -1)
        .map(\.id) == snippets.prefix(3).map(\.id)
    )
    #expect(
      try semanticSnippetMatches(query: "query", snippets: snippets, modelContext: modelContext, embedder: embedder, limit: 10, minimumSimilarity: 0)
        .map(\.id) == snippets.prefix(4).map(\.id)
    )
    #expect(try searchSnippets(query: "query", modelContext: modelContext, embedder: embedder).semanticMatches.count <= semanticMatchLimit)
  }
}
