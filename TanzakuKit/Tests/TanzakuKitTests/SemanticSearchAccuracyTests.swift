import Foundation
import NaturalLanguage
import SwiftData
import Testing

@testable import TanzakuKit

/// NLContextualEmbedding の日本語のモデルで、言い換えたクエリから目的のスニペットが上位 3 件に入る割合を測る。
///
/// 値の良し悪しでは落とさず、測った値を出力する (PR の説明と、`semanticMatchMinimumSimilarity` の決定に使う)。
/// 埋め込みモデルの資産は OS がダウンロードするため、ダウンロードできない環境では実行しない。
struct SemanticSearchAccuracyTests {
  @Test(
    "言い換えたクエリで目的のスニペットが上位 3 件に入る割合を出力する",
    .enabled("NLContextualEmbedding の日本語の資産をダウンロードできる環境だけで測る") {
      try await requestContextualEmbeddingAssets(language: .japanese)
    }
  )
  func topThreeHitRate() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let snippets = semanticSearchFixtureSnippets.map { fixtureSnippet in
      let snippet = Snippet(body: fixtureSnippet.body)
      snippet.title = fixtureSnippet.title
      modelContext.insert(snippet)
      return snippet
    }
    let embedder = try #require(try makeContextualSnippetTextEmbedder(language: .japanese))
    try updateSnippetEmbeddings(modelContext: modelContext, embedder: embedder)
    let vectorsBySnippetID = Dictionary(
      uniqueKeysWithValues: try modelContext.fetch(FetchDescriptor<SnippetEmbedding>()).map { ($0.snippetID, snippetEmbeddingVector(data: $0.vector)) }
    )
    let similarity: (String, Snippet) throws -> Float = { query, snippet in
      zip(l2NormalizedVector(vector: try embedder.vector(query)), vectorsBySnippetID[snippet.id] ?? []).reduce(0) { $0 + $1.0 * $1.1 }
    }

    let topThreeHitCount = try zip(semanticSearchFixtureSnippets, snippets).filter { fixtureSnippet, snippet in
      try semanticSnippetMatches(
        query: fixtureSnippet.paraphrasedQuery,
        snippets: snippets,
        modelContext: modelContext,
        embedder: embedder,
        limit: 3,
        minimumSimilarity: -1
      ).contains { $0.id == snippet.id }
    }.count
    let thresholdedHitCount = try zip(semanticSearchFixtureSnippets, snippets).filter { fixtureSnippet, snippet in
      try semanticSnippetMatches(
        query: fixtureSnippet.paraphrasedQuery,
        snippets: snippets,
        modelContext: modelContext,
        embedder: embedder,
        limit: semanticMatchLimit,
        minimumSimilarity: semanticMatchMinimumSimilarity
      ).contains { $0.id == snippet.id }
    }.count
    let targetSimilarities = try zip(semanticSearchFixtureSnippets, snippets).map { try similarity($0.paraphrasedQuery, $1) }.sorted()
    let unrelatedTopSimilarities = try semanticSearchFixtureUnrelatedQueries.map { query in
      try snippets.map { try similarity(query, $0) }.max() ?? -1
    }.sorted()

    // スニペットの本文は出力しない (`.claude/rules/snippet-content-handling.md`)。出すのは件数と類似度だけ。
    print(
      """
      [SemanticSearchAccuracy] model=\(embedder.modelIdentifier) \
      top3HitRate=\(Double(topThreeHitCount) / Double(snippets.count)) (\(topThreeHitCount)/\(snippets.count)) \
      thresholdedHitRate=\(Double(thresholdedHitCount) / Double(snippets.count)) (\(thresholdedHitCount)/\(snippets.count), \
      minimumSimilarity=\(semanticMatchMinimumSimilarity)) \
      targetSimilarities=\(targetSimilarities) \
      unrelatedTopSimilarities=\(unrelatedTopSimilarities)
      """
    )
    #expect(snippets.count >= 20)
  }
}
