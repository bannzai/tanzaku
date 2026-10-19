import Foundation
import NaturalLanguage
import SwiftData
import Testing

@testable import TanzakuKit

/// Jev (TypeSafe の判定 API) で埋め込みの上位の候補を並べ替える方法を、`SemanticSearchMethodComparisonTests` と同じ fixture・同じ選び方で今の既定と比べる (issue #64)。
///
/// 実際の API を呼ぶため、環境変数 `TYPESAFE_API_KEY` に API キーがある時だけ測る (CI では測らない)。xcodebuild では `TEST_RUNNER_TYPESAFE_API_KEY` で渡す。
/// 要求はアプリと同じ `jevRerankRequest(query:candidateTexts:apiKey:)` で作り、秘匿情報らしい文字列を伏せた後のテキストを送る。
/// 値の良し悪しでは落とさず、測った値を `[SemanticSearchJev]` で始まる行に出力する。スニペットの本文・クエリ・API キー・応答の本文は出力しない (`.claude/rules/snippet-content-handling.md`)。
struct SemanticSearchJevComparisonTests {
  @Test(
    "Jev で並べ替える候補の件数ごとに、上位 3 件の割合・関係の無いクエリで 0 件になる割合・1 件の検索の時間・トークン数を出力する",
    .enabled("環境変数 TYPESAFE_API_KEY と NLContextualEmbedding の日本語の資産がある環境だけで測る") {
      guard ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"]?.isEmpty == false else {
        return false
      }
      return try await requestContextualEmbeddingAssets(language: .japanese)
    }
  )
  @MainActor
  func compareJevRerank() async throws {
    let apiKey = try #require(ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"])
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let snippets = semanticSearchFixtureSnippets.map { fixtureSnippet in
      let snippet = Snippet(body: fixtureSnippet.body)
      snippet.title = fixtureSnippet.title
      modelContext.insert(snippet)
      return snippet
    }
    let snippetSourceTexts = snippets.map { snippetEmbeddingSourceText(snippet: $0) }
    let paraphrasedQueries = semanticSearchFixtureSnippets.map(\.paraphrasedQuery)
    let unrelatedQueries = semanticSearchFixtureUnrelatedQueries
    let embedder = try #require(try makeContextualSnippetTextEmbedder(language: .japanese))
    let snippetVectors = try snippetSourceTexts.map { l2NormalizedVector(vector: try embedder.vector($0)) }
    let similaritiesByQuery: ([String]) throws -> [[Float]] = { queries in
      try queries.map { cosineSimilarities(queryVector: l2NormalizedVector(vector: try embedder.vector($0)), snippetVectors: snippetVectors) }
    }
    let paraphrasedSimilarities = try similaritiesByQuery(paraphrasedQueries)
    let unrelatedSimilarities = try similaritiesByQuery(unrelatedQueries)

    for candidateCount in [10, 15, 20, snippets.count] {
      let recallHitCount = paraphrasedSimilarities.indices.filter { queryIndex in
        topSimilarityIndices(similarities: paraphrasedSimilarities[queryIndex], limit: candidateCount).contains(queryIndex)
      }.count
      print("[SemanticSearchJev] recall candidateCount=\(candidateCount) hits=\(recallHitCount)/\(paraphrasedQueries.count)")
      var errorDescriptions: [String] = []
      var requestSeconds: [Double] = []
      var inputTokens: [Double] = []
      var outputTokens: [Double] = []
      let rerankedIndices: ([String], [[Float]]) async -> [[Int]] = { queries, similarities in
        var results: [[Int]] = []
        for queryIndex in queries.indices {
          let candidateIndices = topSimilarityIndices(similarities: similarities[queryIndex], limit: candidateCount)
          let startedAt = Date.now
          do {
            results.append(
              try await jevRerankedCandidateIndices(
                query: queries[queryIndex],
                candidateTexts: candidateIndices.map { snippetSourceTexts[$0] },
                apiKey: apiKey,
                sendJevRequest: { request in
                  let (data, response) = try await URLSession.shared.data(for: request)
                  let usage = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["usage"] as? [String: Any]
                  // 失敗した要求の応答には usage が無く、件数は errors の行に出るため、トークン数を持つ応答だけを数える (NaN を混ぜると並べ替えの順序が定まらない)。
                  if let inputTokenCount = usage?["input_tokens"] as? Double {
                    inputTokens.append(inputTokenCount)
                  }
                  if let outputTokenCount = usage?["output_tokens"] as? Double {
                    outputTokens.append(outputTokenCount)
                  }
                  return (data, response)
                }
              ).map { candidateIndices[$0] }
            )
          } catch {
            errorDescriptions.append(error is JevRequestError ? String(describing: error) : String(describing: type(of: error)))
            // 失敗した検索は、アプリと同じく今の既定 (埋め込み + しきい値) の結果に戻る。
            results.append(
              topSimilarityIndices(similarities: similarities[queryIndex], limit: semanticMatchLimit).filter {
                similarities[queryIndex][$0] > semanticMatchMinimumSimilarity
              }
            )
          }
          requestSeconds.append(Date.now.timeIntervalSince(startedAt))
        }
        return results
      }
      let paraphrasedResults = await rerankedIndices(paraphrasedQueries, paraphrasedSimilarities)
      let unrelatedResults = await rerankedIndices(unrelatedQueries, unrelatedSimilarities)
      let row = SemanticSearchComparisonRow(
        embeddingName: "jev-rerank-top\(candidateCount)",
        ruleName: "jev-noul",
        parameter: Float(jevRerankMinimumNoul),
        paraphrasedQueryHits: paraphrasedResults.indices.map { paraphrasedResults[$0].contains($0) },
        unrelatedQueryZeroResults: unrelatedResults.map(\.isEmpty)
      )
      print("[SemanticSearchJev] \(row.description)")
      print(
        "[SemanticSearchJev] \(semanticSearchSecondsDistributionDescription(name: "jev-rerank-top\(candidateCount)", seconds: requestSeconds))"
      )
      print(
        "[SemanticSearchJev] \(semanticSearchSecondsDistributionDescription(name: "jev-rerank-top\(candidateCount)-input-tokens", seconds: inputTokens))"
      )
      print(
        "[SemanticSearchJev] \(semanticSearchSecondsDistributionDescription(name: "jev-rerank-top\(candidateCount)-output-tokens", seconds: outputTokens))"
      )
      let countsByDescription = Dictionary(grouping: errorDescriptions, by: { $0 }).mapValues(\.count).sorted { $0.key < $1.key }
      print("[SemanticSearchJev] errors name=jev-rerank-top\(candidateCount) count=\(errorDescriptions.count) types=\(countsByDescription.map { "\($0.key):\($0.value)" })")
    }
    #expect(snippets.count >= 20)
  }
}
