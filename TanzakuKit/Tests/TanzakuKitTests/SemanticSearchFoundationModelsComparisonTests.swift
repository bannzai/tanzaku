import Foundation
import NaturalLanguage
import SwiftData
import Testing

@testable import TanzakuKit

#if canImport(FoundationModels)
  import FoundationModels
#endif

/// 端末内の言語モデル (Foundation Models の `SystemLanguageModel`) を意味検索に使う方法を、`SemanticSearchMethodComparisonTests` と同じ fixture・同じ選び方で今の既定と比べる (issue #63)。
///
/// 値の良し悪しでは落とさず、測った値を `[SemanticSearchFoundationModels]` で始まる行に出力する。
/// スニペットの本文・クエリ・言語モデルの応答は出力せず、件数・割合・時間・エラーの型の名前だけを出す (`.claude/rules/snippet-content-handling.md`。応答はスニペットの本文を写し得るため)。
///
/// 指示文・候補の件数・貪欲な選び方 (`GenerationOptions(sampling: .greedy)`)・選び方 (`semanticSearchComparisonIsWorse`)・速さの基準 (`foundationModelsQueryMedianSecondsLimit`) は、測る前にこのファイルに書いて決めた。
struct SemanticSearchFoundationModelsComparisonTests {
  @Test("端末内の言語モデルを使えるかを出力する (CI のランナーで使えるかを確かめるため、使えない環境でも実行する)")
  func printAvailability() {
    print("[SemanticSearchFoundationModels] availability=\(foundationModelsAvailabilityDescription())")
  }

  #if canImport(FoundationModels)
    @available(macOS 26.0, iOS 26.0, *)
    @Test(
      "言語モデルを使う方法ごとに、上位 3 件の割合・関係の無いクエリで 0 件になる割合・1 件の検索の時間を出力する",
      .enabled("端末内の言語モデルと NLContextualEmbedding の日本語の資産を使える環境だけで測る") {
        guard #available(macOS 26.0, iOS 26.0, *), SystemLanguageModel.default.isAvailable else {
          return false
        }
        return try await requestContextualEmbeddingAssets(language: .japanese)
      }
    )
    @MainActor
    func compareFoundationModelsMethods() async throws {
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
      var embeddingSeconds: [Double] = []
      let similaritiesByQuery: ([String]) throws -> [[Float]] = { queries in
        try queries.map { query in
          let startedAt = Date.now
          let queryVector = l2NormalizedVector(vector: try embedder.vector(query))
          embeddingSeconds.append(Date.now.timeIntervalSince(startedAt))
          return cosineSimilarities(queryVector: queryVector, snippetVectors: snippetVectors)
        }
      }
      let paraphrasedSimilarities = try similaritiesByQuery(paraphrasedQueries)
      let unrelatedSimilarities = try similaritiesByQuery(unrelatedQueries)
      printSecondsDistribution(name: "embedding-query", seconds: embeddingSeconds)

      // 並べ替えは埋め込みの上位 N 件の外にある目的のスニペットを拾えないため、N ごとの上限 (埋め込みの上位 N 件に目的のスニペットが入る割合) を先に出す。
      for candidateCount in [3, 5, 10, snippets.count] {
        let hitCount = paraphrasedSimilarities.indices.filter { queryIndex in
          topSimilarityIndices(similarities: paraphrasedSimilarities[queryIndex], limit: candidateCount).contains(queryIndex)
        }.count
        print("[SemanticSearchFoundationModels] recall candidateCount=\(candidateCount) hits=\(hitCount)/\(paraphrasedQueries.count)")
      }

      // 測った時間に言語モデルの読み込みを含めないよう、スニペットではない固定の文字列で 1 回呼んでから測る。1 回目の時間は別に出す。
      let coldStartedAt = Date.now
      _ = try? await foundationModelsQueryExpansion(query: "ダミーの検索語")
      print(String(format: "[SemanticSearchFoundationModels] coldFirstCallSeconds=%.3f", Date.now.timeIntervalSince(coldStartedAt)))

      var rows: [SemanticSearchComparisonRow] = []
      let appendRows: (String, [[Float]], [[Float]]) -> Void = { embeddingName, paraphrased, unrelated in
        for rule in semanticSearchComparisonRules {
          let row = SemanticSearchComparisonRow(
            embeddingName: embeddingName,
            ruleName: rule.name,
            parameter: rule.parameter,
            paraphrasedQueryHits: paraphrased.indices.map { rule.matchIndices(paraphrased[$0]).contains($0) },
            unrelatedQueryZeroResults: unrelated.map { rule.matchIndices($0).isEmpty }
          )
          rows.append(row)
          print("[SemanticSearchFoundationModels] \(row.description)")
        }
      }
      appendRows("baseline-mean", paraphrasedSimilarities, unrelatedSimilarities)

      // 方法 1: 埋め込みの上位 N 件を言語モデルに渡し、検索語に当てはまる候補 (0〜3 件) を選ばせる。
      for candidateCount in foundationModelsRerankCandidateCounts {
        var errorTypeNames: [String] = []
        var rerankSeconds: [Double] = []
        let rerankedIndices: ([String], [[Float]]) async -> [[Int]] = { queries, similarities in
          var results: [[Int]] = []
          for queryIndex in queries.indices {
            let candidateIndices = topSimilarityIndices(similarities: similarities[queryIndex], limit: candidateCount)
            let startedAt = Date.now
            do {
              results.append(
                try await foundationModelsRerank(
                  query: queries[queryIndex],
                  candidateTexts: candidateIndices.map { snippetSourceTexts[$0] }
                ).map { candidateIndices[$0] }
              )
            } catch {
              errorTypeNames.append(String(describing: type(of: error)))
              // 言語モデルが答えなかった検索は、今の既定 (埋め込み + しきい値) の結果に戻る。
              results.append(
                topSimilarityIndices(similarities: similarities[queryIndex], limit: semanticMatchLimit).filter {
                  similarities[queryIndex][$0] > semanticMatchMinimumSimilarity
                }
              )
            }
            rerankSeconds.append(Date.now.timeIntervalSince(startedAt))
          }
          return results
        }
        let paraphrasedResults = await rerankedIndices(paraphrasedQueries, paraphrasedSimilarities)
        let unrelatedResults = await rerankedIndices(unrelatedQueries, unrelatedSimilarities)
        let row = SemanticSearchComparisonRow(
          embeddingName: "rerank-top\(candidateCount)",
          ruleName: "foundation-models",
          parameter: Float(candidateCount),
          paraphrasedQueryHits: paraphrasedResults.indices.map { paraphrasedResults[$0].contains($0) },
          unrelatedQueryZeroResults: unrelatedResults.map(\.isEmpty)
        )
        rows.append(row)
        print("[SemanticSearchFoundationModels] \(row.description)")
        printSecondsDistribution(name: "rerank-top\(candidateCount)-foundation-models", seconds: rerankSeconds)
        printErrorTypeNames(name: "rerank-top\(candidateCount)", errorTypeNames: errorTypeNames)
      }

      // 方法 2: 検索語を言語モデルで言い換え、元の検索語と言い換えのうち最も近いものの類似度でスニペットを比べる。
      do {
        var errorTypeNames: [String] = []
        var expansionSeconds: [Double] = []
        let expandedSimilarities: ([String]) async throws -> [[Float]] = { queries in
          var results: [[Float]] = []
          for query in queries {
            let startedAt = Date.now
            var expandedQueries = [query]
            do {
              expandedQueries += try await foundationModelsQueryExpansion(query: query)
            } catch {
              errorTypeNames.append(String(describing: type(of: error)))
            }
            expansionSeconds.append(Date.now.timeIntervalSince(startedAt))
            let similaritiesByExpandedQuery = try expandedQueries.map { expandedQuery in
              cosineSimilarities(queryVector: l2NormalizedVector(vector: try embedder.vector(expandedQuery)), snippetVectors: snippetVectors)
            }
            results.append(snippetVectors.indices.map { snippetIndex in similaritiesByExpandedQuery.map { $0[snippetIndex] }.max() ?? -1 })
          }
          return results
        }
        appendRows("query-expansion", try await expandedSimilarities(paraphrasedQueries), try await expandedSimilarities(unrelatedQueries))
        printSecondsDistribution(name: "query-expansion-foundation-models", seconds: expansionSeconds)
        printErrorTypeNames(name: "query-expansion", errorTypeNames: errorTypeNames)
      }

      // 方法 3: スニペットの保存時に言語モデルで説明と検索語を作り、ベクトルの元のテキストに足す。検索の時は言語モデルを呼ばない。
      var errorTypeNames: [String] = []
      var indexSeconds: [Double] = []
      var indexedSourceTexts: [String] = []
      for sourceText in snippetSourceTexts {
        let startedAt = Date.now
        do {
          indexedSourceTexts.append(sourceText + "\n" + (try await foundationModelsSnippetSearchText(snippetSourceText: sourceText)))
        } catch {
          errorTypeNames.append(String(describing: type(of: error)))
          indexedSourceTexts.append(sourceText)
        }
        indexSeconds.append(Date.now.timeIntervalSince(startedAt))
      }
      printSecondsDistribution(name: "index-time-foundation-models-per-snippet", seconds: indexSeconds)
      printErrorTypeNames(name: "index-time", errorTypeNames: errorTypeNames)
      let indexedSnippetVectors = try indexedSourceTexts.map { l2NormalizedVector(vector: try embedder.vector($0)) }
      let indexedSimilaritiesByQuery: ([String]) throws -> [[Float]] = { queries in
        try queries.map { cosineSimilarities(queryVector: l2NormalizedVector(vector: try embedder.vector($0)), snippetVectors: indexedSnippetVectors) }
      }
      appendRows("index-time", try indexedSimilaritiesByQuery(paraphrasedQueries), try indexedSimilaritiesByQuery(unrelatedQueries))

      let bestRow = try #require(rows.max { semanticSearchComparisonIsWorse(row: $0, otherRow: $1) })
      print("[SemanticSearchFoundationModels] best \(bestRow.description)")
      #expect(snippets.count >= 20)
      #expect(unrelatedQueries.count >= 20)
    }
  #endif
}

/// 方法 1 (並べ替え) で言語モデルに渡す候補の件数。全件 (26) は fixture のスニペットすべてで、実際のライブラリでは件数が増えるため、並べ替えの上限を測る比較として置く。
///
/// 10 件は、埋め込みの上位 3 件より広く拾い、候補の本文 (`foundationModelsRerankCandidateMaxLength` 文字まで) を足しても 1 回のやり取りの 4096 トークンに収まる件数
/// ( https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window )。
let foundationModelsRerankCandidateCounts = [10, 26]

/// 並べ替えで言語モデルに渡す候補 1 件のテキストの最大の文字数。26 件を渡しても 4096 トークンに収まるよう、タイトルと本文の先頭だけを渡す。
let foundationModelsRerankCandidateMaxLength = 120

/// 「ランチャーで打つたびの検索に使える速さ」の基準 (1 件の検索の時間の中央値の上限、秒)。
///
/// ランチャーは文字列の一致をすぐに出し、打つたびに前の意味検索を取り消して始め直す (`LauncherPanelController.search`)。
/// 1 件の検索がこれより長いと、打ち終えてから意味検索の欄が埋まるまでの待ちが、今の埋め込みの検索 (CI の実測で 1 件数十ミリ秒) と比べて目立つため、測る前に 0.5 秒と決めた。
let foundationModelsQueryMedianSecondsLimit = 0.5

/// 言語モデルを使えるかを出力に書く文字列。使えない時は理由 (`SystemLanguageModel.Availability.UnavailableReason`) を書く。
func foundationModelsAvailabilityDescription() -> String {
  #if canImport(FoundationModels)
    if #available(macOS 26.0, iOS 26.0, *) {
      return String(describing: SystemLanguageModel.default.availability)
    }
    return "unavailable(os-before-26)"
  #else
    return "unavailable(no-FoundationModels-sdk)"
  #endif
}

/// クエリのベクトルと各スニペットのベクトル (どちらも長さ 1) の内積 (コサイン類似度)。
func cosineSimilarities(queryVector: [Float], snippetVectors: [[Float]]) -> [Float] {
  snippetVectors.map { snippetVector in zip(queryVector, snippetVector).reduce(0) { $0 + $1.0 * $1.1 } }
}

/// 類似度の高い順に `limit` 件の添字。
func topSimilarityIndices(similarities: [Float], limit: Int) -> [Int] {
  Array(similarities.indices.sorted { similarities[$0] > similarities[$1] }.prefix(limit))
}

/// 時間の中央値・90 パーセンタイル・最大を出力する。
func printSecondsDistribution(name: String, seconds: [Double]) {
  print("[SemanticSearchFoundationModels] \(semanticSearchSecondsDistributionDescription(name: name, seconds: seconds))")
}

/// 測った値 (時間・トークン数) の件数・中央値・90 パーセンタイル・最大を 1 行の文字列にする。
func semanticSearchSecondsDistributionDescription(name: String, seconds: [Double]) -> String {
  let sortedSeconds = seconds.sorted()
  let percentile: (Double) -> Double = { ratio in
    sortedSeconds.isEmpty ? .nan : sortedSeconds[min(Int((Double(sortedSeconds.count - 1) * ratio).rounded()), sortedSeconds.count - 1)]
  }
  return String(
    format: "seconds name=%@ count=%d median=%.3f p90=%.3f max=%.3f",
    name, sortedSeconds.count, percentile(0.5), percentile(0.9), sortedSeconds.last ?? .nan
  )
}

/// 言語モデルのエラーの件数を型の名前ごとに出力する。エラーの内容は応答や入力を含み得るため出さない。
func printErrorTypeNames(name: String, errorTypeNames: [String]) {
  let countsByTypeName = Dictionary(grouping: errorTypeNames, by: { $0 }).mapValues(\.count).sorted { $0.key < $1.key }
  print("[SemanticSearchFoundationModels] errors name=\(name) count=\(errorTypeNames.count) types=\(countsByTypeName.map { "\($0.key):\($0.value)" })")
}

#if canImport(FoundationModels)
  /// 並べ替えの応答。検索語に当てはまる候補の番号。
  @available(macOS 26.0, iOS 26.0, *)
  @Generable
  struct FoundationModelsRerankResponse {
    @Guide(description: "Numbers of the candidates that match the search query, best match first. At most 3. Empty when no candidate matches.")
    var matchingCandidateNumbers: [Int]
  }

  /// 検索語の言い換えの応答。
  @available(macOS 26.0, iOS 26.0, *)
  @Generable
  struct FoundationModelsQueryExpansionResponse {
    @Guide(description: "Short phrases or keywords that describe the snippet the user is looking for, in Japanese and English.", .count(5))
    var phrases: [String]
  }

  /// スニペットの検索のための説明と検索語の応答。
  @available(macOS 26.0, iOS 26.0, *)
  @Generable
  struct FoundationModelsSnippetSearchTextResponse {
    @Guide(description: "One sentence that describes what the snippet does or is used for, in Japanese.")
    var japaneseDescription: String
    @Guide(description: "One sentence that describes what the snippet does or is used for, in English.")
    var englishDescription: String
    @Guide(description: "Words a user might type to find this snippet, in Japanese and English.", .count(8))
    var keywords: [String]
  }

  /// 測る時の言語モデルの選び方。同じ入力に同じ応答を返させ、測り直しても同じ値になるようにする。
  @available(macOS 26.0, iOS 26.0, *)
  var foundationModelsComparisonGenerationOptions: GenerationOptions {
    GenerationOptions(sampling: .greedy)
  }

  /// 検索語と候補のテキスト (`snippetEmbeddingSourceText` の形) を言語モデルに渡し、検索語に当てはまる候補の添字 (`candidateTexts` の添字) を最大 3 件、当てはまる順に返す。
  /// 冪等ではない: 貪欲な選び方でも、OS の言語モデルの版が変わると応答が変わり得る。
  @available(macOS 26.0, iOS 26.0, *)
  func foundationModelsRerank(query: String, candidateTexts: [String]) async throws -> [Int] {
    let response = try await LanguageModelSession(
      model: SystemLanguageModel.default,
      instructions:
        "You are the search engine of a snippet app. Snippets are reusable text, shell commands, code, or prompts. Given a search query and numbered candidate snippets, choose the candidates whose purpose matches what the user wants. The query may use different words or another language than the snippet. Choose none when no candidate matches the purpose of the query."
    ).respond(
      to: "Search query: \(query)\n\nCandidates:\n"
        + candidateTexts.indices.map { "[\($0 + 1)] \(candidateTexts[$0].prefix(foundationModelsRerankCandidateMaxLength).replacingOccurrences(of: "\n", with: " / "))" }
        .joined(separator: "\n"),
      generating: FoundationModelsRerankResponse.self,
      options: foundationModelsComparisonGenerationOptions
    ).content
    var candidateIndices: [Int] = []
    for candidateNumber in response.matchingCandidateNumbers where candidateTexts.indices.contains(candidateNumber - 1) && !candidateIndices.contains(candidateNumber - 1) {
      candidateIndices.append(candidateNumber - 1)
    }
    return Array(candidateIndices.prefix(semanticMatchLimit))
  }

  /// 検索語を言語モデルで言い換えた語句を返す。
  /// 冪等ではない: 貪欲な選び方でも、OS の言語モデルの版が変わると応答が変わり得る。
  @available(macOS 26.0, iOS 26.0, *)
  func foundationModelsQueryExpansion(query: String) async throws -> [String] {
    try await LanguageModelSession(
      model: SystemLanguageModel.default,
      instructions:
        "You help a snippet app search. Snippets are reusable text, shell commands, code, or prompts. Rewrite the user's search query into short phrases or keywords that a matching snippet would contain, such as command names, technical terms, and typical wording."
    ).respond(
      to: "Search query: \(query)",
      generating: FoundationModelsQueryExpansionResponse.self,
      options: foundationModelsComparisonGenerationOptions
    ).content.phrases
  }

  /// スニペット (`snippetEmbeddingSourceText` の形) の説明と検索語を言語モデルで作り、改行でつないで返す。
  /// 冪等ではない: 貪欲な選び方でも、OS の言語モデルの版が変わると応答が変わり得る。
  @available(macOS 26.0, iOS 26.0, *)
  func foundationModelsSnippetSearchText(snippetSourceText: String) async throws -> String {
    let response = try await LanguageModelSession(
      model: SystemLanguageModel.default,
      instructions:
        "You help a snippet app search. Snippets are reusable text, shell commands, code, or prompts. Describe what the given snippet does or is used for, and list words a user might type to find it."
    ).respond(
      to: "Snippet:\n\(snippetSourceText.prefix(1500))",
      generating: FoundationModelsSnippetSearchTextResponse.self,
      options: foundationModelsComparisonGenerationOptions
    ).content
    return ([response.japaneseDescription, response.englishDescription] + response.keywords).joined(separator: "\n")
  }
#endif
