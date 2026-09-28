import Foundation
import NaturalLanguage
import SwiftData
import Testing

@testable import TanzakuKit

/// 意味検索の方法 (埋め込みモデル・トークンのベクトルの集約・類似度の扱い) を同じ fixture で比べ、方法ごとの精度を出力する。
///
/// 値の良し悪しでは落とさず、測った値を `[SemanticSearchComparison]` で始まる行に出力する (PR の説明と、`TanzakuKit` の既定の方法の決定に使う)。
/// スニペットの本文とクエリは出力せず、件数と類似度だけを出す (`.claude/rules/snippet-content-handling.md`)。
struct SemanticSearchMethodComparisonTests {
  @Test(
    "埋め込みモデル・集約・類似度の扱いの組み合わせごとに、上位 3 件の割合と関係の無いクエリで 0 件になる割合を出力する",
    .enabled("NLContextualEmbedding の日本語の資産をダウンロードできる環境だけで測る") {
      try await requestContextualEmbeddingAssets(language: .japanese)
    }
  )
  func compareMethods() throws {
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

    let contextualEmbedding = try #require(NLContextualEmbedding(language: .japanese))
    try contextualEmbedding.load()
    printContextualTokenDiagnostics(embedding: contextualEmbedding)
    let contextualModelIdentifier = "contextual:\(contextualEmbedding.modelIdentifier)@\(contextualEmbedding.revision)"
    var embedders = [
      SnippetTextEmbedder(modelIdentifier: "\(contextualModelIdentifier)/mean") { text in
        meanTokenVector(
          tokenVectors: try contextualTokenVectorsByChunk(embedding: contextualEmbedding, language: .japanese, text: text).flatMap { $0 },
          dimension: contextualEmbedding.dimension
        )
      },
      SnippetTextEmbedder(modelIdentifier: "\(contextualModelIdentifier)/max") { text in
        maxTokenVector(
          tokenVectors: try contextualTokenVectorsByChunk(embedding: contextualEmbedding, language: .japanese, text: text).flatMap { $0 },
          dimension: contextualEmbedding.dimension
        )
      },
      SnippetTextEmbedder(modelIdentifier: "\(contextualModelIdentifier)/mean-without-first-and-last") { text in
        meanTokenVector(
          tokenVectors: try contextualTokenVectorsByChunk(embedding: contextualEmbedding, language: .japanese, text: text).flatMap { chunkTokenVectors in
            // トークンが 2 つ以下の区切りは、先頭と末尾を除くと何も残らないためそのまま使う。
            chunkTokenVectors.count > 2 ? Array(chunkTokenVectors.dropFirst().dropLast()) : chunkTokenVectors
          },
          dimension: contextualEmbedding.dimension
        )
      },
    ]
    if let sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .japanese) {
      print("[SemanticSearchComparison] sentenceEmbedding=available dimension=\(sentenceEmbedding.dimension) revision=\(sentenceEmbedding.revision)")
      embedders.append(
        SnippetTextEmbedder(modelIdentifier: "sentence:ja@\(sentenceEmbedding.revision)") { text in
          (sentenceEmbedding.vector(for: text) ?? [Double](repeating: 0, count: sentenceEmbedding.dimension)).map { Float($0) }
        }
      )
    } else {
      print("[SemanticSearchComparison] sentenceEmbedding=unavailable")
    }

    printKeywordOnlyRow(snippets: snippets, paraphrasedQueries: paraphrasedQueries, unrelatedQueries: unrelatedQueries)

    var rows: [SemanticSearchComparisonRow] = []
    for embedder in embedders {
      let snippetVectors = try snippetSourceTexts.map { l2NormalizedVector(vector: try embedder.vector($0)) }
      let similaritiesByQuery: ([String]) throws -> [[Float]] = { queries in
        try queries.map { query in
          let queryVector = l2NormalizedVector(vector: try embedder.vector(query))
          return snippetVectors.map { snippetVector in zip(queryVector, snippetVector).reduce(0) { $0 + $1.0 * $1.1 } }
        }
      }
      let paraphrasedSimilarities = try similaritiesByQuery(paraphrasedQueries)
      let unrelatedSimilarities = try similaritiesByQuery(unrelatedQueries)
      printSimilarityDistribution(
        embeddingName: embedder.modelIdentifier,
        paraphrasedSimilarities: paraphrasedSimilarities,
        unrelatedSimilarities: unrelatedSimilarities
      )
      for rule in semanticSearchComparisonRules {
        let row = SemanticSearchComparisonRow(
          embeddingName: embedder.modelIdentifier,
          ruleName: rule.name,
          parameter: rule.parameter,
          topThreeHitCount: paraphrasedSimilarities.indices.filter { rule.matchIndices(paraphrasedSimilarities[$0]).contains($0) }.count,
          queryCount: paraphrasedSimilarities.count,
          unrelatedZeroResultCount: unrelatedSimilarities.filter { rule.matchIndices($0).isEmpty }.count,
          unrelatedQueryCount: unrelatedSimilarities.count
        )
        rows.append(row)
        print("[SemanticSearchComparison] \(row.description)")
      }
    }
    let bestRow = try #require(rows.max { semanticSearchComparisonIsWorse(row: $0, otherRow: $1) })
    print("[SemanticSearchComparison] best \(bestRow.description)")
    #expect(snippets.count >= 20)
    #expect(unrelatedQueries.count >= 20)
  }
}

/// 比べた方法 1 つの結果。出力の 1 行になる。
struct SemanticSearchComparisonRow: CustomStringConvertible {
  /// 埋め込みモデルと集約の名前。
  var embeddingName: String
  /// 類似度の扱いの名前。
  var ruleName: String
  /// 類似度の扱いのしきい値。
  var parameter: Float
  /// 言い換えたクエリで、目的のスニペットが結果 (最大 3 件) に入った数。
  var topThreeHitCount: Int
  /// 言い換えたクエリの数。
  var queryCount: Int
  /// 関係の無いクエリで、意味検索の結果が 0 件になった数。
  var unrelatedZeroResultCount: Int
  /// 関係の無いクエリの数。
  var unrelatedQueryCount: Int

  /// 上位 3 件の割合。
  var topThreeHitRate: Double {
    Double(topThreeHitCount) / Double(queryCount)
  }

  /// 関係の無いクエリで 0 件になる割合。
  var unrelatedZeroResultRate: Double {
    Double(unrelatedZeroResultCount) / Double(unrelatedQueryCount)
  }

  /// `[SemanticSearchComparison]` の後に続く出力の 1 行。CI のログから表を作るため、項目を `名前=値` の形で並べる。
  var description: String {
    [
      "embedding=\(embeddingName)",
      "rule=\(ruleName)",
      String(format: "parameter=%.2f", parameter),
      "top3=\(topThreeHitCount)/\(queryCount)" + String(format: "(%.3f)", topThreeHitRate),
      "unrelatedZero=\(unrelatedZeroResultCount)/\(unrelatedQueryCount)" + String(format: "(%.3f)", unrelatedZeroResultRate),
      String(format: "score=%.3f", topThreeHitRate + unrelatedZeroResultRate),
    ].joined(separator: " ")
  }
}

/// 既定にする方法の選び方。上位 3 件の割合と関係の無いクエリで 0 件になる割合の和が大きい方を良いとし、同じなら上位 3 件の割合が高い方を良いとする。
///
/// 和にするのは、目的のスニペットを出せないことと関係の無い結果を出すことを同じ重さで扱うため。関係の無い結果を常に 3 件出すと検索全体の信頼を下げ (issue #24)、
/// 目的のスニペットを出せなければ意味検索の欄が役に立たない。同じ和なら、意味検索の欄の役目 (言い換えで見つける) を優先する。
func semanticSearchComparisonIsWorse(row: SemanticSearchComparisonRow, otherRow: SemanticSearchComparisonRow) -> Bool {
  let score = row.topThreeHitRate + row.unrelatedZeroResultRate
  let otherScore = otherRow.topThreeHitRate + otherRow.unrelatedZeroResultRate
  if score != otherScore {
    return score < otherScore
  }
  return row.topThreeHitRate < otherRow.topThreeHitRate
}

/// 比べる類似度の扱い。`matchIndices` はクエリと全スニペットの類似度から、結果に出すスニペットの添字を類似度の高い順に最大 3 件返す。
///
/// しきい値は、測った類似度 (PR #23 の 0.46〜0.91) と z スコアの範囲を覆う刻みで並べる。
var semanticSearchComparisonRules: [(name: String, parameter: Float, matchIndices: ([Float]) -> [Int])] {
  var rules: [(name: String, parameter: Float, matchIndices: ([Float]) -> [Int])] = [
    (name: "none", parameter: -1, matchIndices: { similarities in topSimilarityIndices(similarities: similarities) { _ in true } })
  ]
  for minimumSimilarity in stride(from: Float(0), through: 0.95, by: 0.05) {
    rules.append(
      (
        name: "absolute", parameter: minimumSimilarity,
        matchIndices: { similarities in topSimilarityIndices(similarities: similarities) { similarities[$0] > minimumSimilarity } }
      )
    )
  }
  for maximumGap: Float in [0.01, 0.02, 0.03, 0.05, 0.1, 0.2] {
    rules.append(
      (
        name: "gap-from-top", parameter: maximumGap,
        matchIndices: { similarities in
          let topSimilarity = similarities.max() ?? 0
          return topSimilarityIndices(similarities: similarities) { similarities[$0] >= topSimilarity - maximumGap }
        }
      )
    )
  }
  for minimumZScore in stride(from: Float(1), through: 4, by: 0.25) {
    rules.append(
      (
        name: "z-score", parameter: minimumZScore,
        matchIndices: { similarities in
          let zScores = similarityZScores(similarities: similarities)
          return topSimilarityIndices(similarities: similarities) { zScores[$0] >= minimumZScore }
        }
      )
    )
  }
  return rules
}

/// 類似度を、そのクエリの全スニペットの類似度の分布に対する z スコアにする。
/// 全部が同じ値の時は分布から外れたスニペットが無いため、平均と同じ位置を表す 0 にする。
func similarityZScores(similarities: [Float]) -> [Float] {
  let mean = similarities.reduce(0, +) / Float(similarities.count)
  let standardDeviation = (similarities.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(similarities.count)).squareRoot()
  return similarities.map { standardDeviation > 0 ? ($0 - mean) / standardDeviation : 0 }
}

/// `isIncluded` を満たす添字を、類似度の高い順に最大 3 件返す。3 件は `semanticMatchLimit` と同じ。
func topSimilarityIndices(similarities: [Float], isIncluded: (Int) -> Bool) -> [Int] {
  Array(similarities.indices.filter(isIncluded).sorted { similarities[$0] > similarities[$1] }.prefix(semanticMatchLimit))
}

/// トークンのベクトルの要素ごとの最大値。トークンが無い時は長さ `dimension` の 0 のベクトルを返す。
func maxTokenVector(tokenVectors: [[Double]], dimension: Int) -> [Float] {
  guard let firstTokenVector = tokenVectors.first else {
    return [Float](repeating: 0, count: dimension)
  }
  return tokenVectors.dropFirst().reduce(firstTokenVector) { maximum, tokenVector in zip(maximum, tokenVector).map { max($0, $1) } }.map { Float($0) }
}

/// NLContextualEmbedding のトークンに、先頭・末尾の特別なトークン (文字列の範囲が空のもの) が含まれるかを出力する。
/// 「先頭と末尾のトークンを除いた平均」が本文のトークンを落としていないかを確かめるため。スニペットではない固定の文字列で調べる。
func printContextualTokenDiagnostics(embedding: NLContextualEmbedding) {
  let text = "ダミーの文章です"
  var tokenRangeLengths: [Int] = []
  do {
    try embedding.embeddingResult(for: text, language: .japanese).enumerateTokenVectors(in: text.startIndex..<text.endIndex) { _, tokenRange in
      tokenRangeLengths.append(text.distance(from: tokenRange.lowerBound, to: tokenRange.upperBound))
      return true
    }
  } catch {
    print("[SemanticSearchComparison] tokenDiagnostics error=\(error)")
    return
  }
  print(
    "[SemanticSearchComparison] tokenDiagnostics characterCount=\(text.count) tokenCount=\(tokenRangeLengths.count) tokenRangeLengths=\(tokenRangeLengths) maximumSequenceLength=\(embedding.maximumSequenceLength) dimension=\(embedding.dimension)"
  )
}

/// 言い換えたクエリの目的のスニペットの類似度と、関係の無いクエリの最も近いスニペットの類似度・z スコアの範囲を出力する。
func printSimilarityDistribution(embeddingName: String, paraphrasedSimilarities: [[Float]], unrelatedSimilarities: [[Float]]) {
  let rangeText: ([Float]) -> String = { values in
    String(format: "%.2f〜%.2f", values.min() ?? .nan, values.max() ?? .nan)
  }
  print(
    [
      "[SemanticSearchComparison] distribution embedding=\(embeddingName)",
      "targetSimilarity=\(rangeText(paraphrasedSimilarities.indices.map { paraphrasedSimilarities[$0][$0] }))",
      "unrelatedTopSimilarity=\(rangeText(unrelatedSimilarities.map { $0.max() ?? .nan }))",
      "targetZScore=\(rangeText(paraphrasedSimilarities.indices.map { similarityZScores(similarities: paraphrasedSimilarities[$0])[$0] }))",
      "unrelatedTopZScore=\(rangeText(unrelatedSimilarities.map { similarityZScores(similarities: $0).max() ?? .nan }))",
    ].joined(separator: " ")
  )
}

/// キーワード検索 (文字列の一致) だけの場合の上位 3 件の割合と、関係の無いクエリで 0 件になる割合を出力する。比較の基準にする。
func printKeywordOnlyRow(snippets: [Snippet], paraphrasedQueries: [String], unrelatedQueries: [String]) {
  let matchedIndices: (String) -> [Int] = { query in
    let normalizedQuery = normalizedSnippetSearchText(text: query.trimmingCharacters(in: .whitespacesAndNewlines))
    let matchKinds = snippets.map { snippetKeywordMatchKind(snippet: $0, normalizedQuery: normalizedQuery) }
    return [SnippetKeywordMatchKind.keywordExact, .keywordPrefix, .titleOrBody].flatMap { kind in matchKinds.indices.filter { matchKinds[$0] == kind } }
  }
  let row = SemanticSearchComparisonRow(
    embeddingName: "keyword-only",
    ruleName: "keyword-only",
    parameter: 0,
    topThreeHitCount: paraphrasedQueries.indices.filter { matchedIndices(paraphrasedQueries[$0]).prefix(3).contains($0) }.count,
    queryCount: paraphrasedQueries.count,
    unrelatedZeroResultCount: unrelatedQueries.filter { matchedIndices($0).isEmpty }.count,
    unrelatedQueryCount: unrelatedQueries.count
  )
  print("[SemanticSearchComparison] \(row.description)")
}
