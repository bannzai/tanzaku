import Foundation
import SwiftData

/// 入力した文字列がスニペットのどこに一致したか。並びは結果に出す順。
public enum SnippetKeywordMatchKind: Equatable, Sendable {
  /// キーワードと完全に一致した。
  case keywordExact
  /// キーワードの先頭と一致した。
  case keywordPrefix
  /// 入力を空白で区切ったすべての語が、タイトルか本文に含まれていた。
  case titleOrBody
}

/// 文字列の一致で見つかった 1 件。
public struct SnippetKeywordMatch {
  /// 見つかったスニペット。
  public var snippet: Snippet
  /// 一致した場所。
  public var kind: SnippetKeywordMatchKind
}

/// 検索の結果。ランチャーは「キーワードが一致」と意味検索の欄を分けて表示するため (`documents/design/Main.dc.html`)、2 つに分けて返す。
public struct SnippetSearchResult {
  /// 入力した文字列がキーワード・タイトル・本文に一致したスニペット。キーワードの完全一致、前方一致、タイトル・本文の一致の順に並び、同じ種類の中は更新日時の新しい順。
  public var keywordMatches: [SnippetKeywordMatch]
  /// 意味検索で見つかったスニペット。`keywordMatches` に入ったものは除き、意味が近い順に並ぶ。
  public var semanticMatches: [Snippet]
}

/// 意味検索の結果に出す最大の件数。ランチャーの意味検索の欄は文字列の一致の欄の下に置く補助の欄のため (`documents/design/Main.dc.html`)、精度のテストで測る「上位 3 件」と同じ件数にとどめる。
let semanticMatchLimit = 3

/// 意味検索の結果に出すコサイン類似度の下限 (この値ちょうどは出さない)。関係の無いクエリで意味検索の欄を空にするための下限。
///
/// 方法の比較のテスト (`SemanticSearchMethodComparisonTests`) の 2026-09-28 の CI (run 36429714401) の実測で、
/// 「上位 3 件の割合 + 関係の無いクエリで 0 件になる割合」が最も大きかった方法 (トークンのベクトルの平均 + 絶対のしきい値 0.65) の値。
/// 上位 3 件の割合は 0.346 (26 件中 9 件。しきい値なしの 0.423 から 2 件減る)、関係の無いクエリで 0 件になる割合は 0.80 (20 件中 16 件) だった。
/// 0.60 では 10 件・15 件、0.70 では 5 件・16 件で、0.65 より上げると目的のスニペットが急に出なくなる。
/// 漢字かなのモデルは英語の文章どうしを近く置くため、英語のクエリは関係が無くても英語のスニペットと 0.84 以上になり、このしきい値では落とせない (`documents/DIRECTION.md`「決めたこと」)。
let semanticMatchMinimumSimilarity: Float = 0.65

/// Mac のランチャー・管理画面、iOS の本体・キーボード・App Intents で共通に使うスニペットの検索。
///
/// `embedder` が `nil` の時 (埋め込みモデルの資産のダウンロードが済んでいない時) は、意味検索なしで文字列の一致だけを返す。
/// 意味検索は、`embedder` と `modelIdentifier` が一致し、今のスニペットから作ったベクトル (`sourceHash` が一致するもの) だけを使う。ベクトルの作成・作り直しは `updateSnippetEmbeddings(modelContext:embedder:)` が行う。
public func searchSnippets(query: String, modelContext: ModelContext, embedder: SnippetTextEmbedder?) throws -> SnippetSearchResult {
  let normalizedQuery = normalizedSnippetSearchText(text: query.trimmingCharacters(in: .whitespacesAndNewlines))
  guard !normalizedQuery.isEmpty else {
    return SnippetSearchResult(keywordMatches: [], semanticMatches: [])
  }
  let snippets = try modelContext.fetch(FetchDescriptor<Snippet>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
  let keywordMatches = snippets.compactMap { snippet in
    snippetKeywordMatchKind(snippet: snippet, normalizedQuery: normalizedQuery).map { SnippetKeywordMatch(snippet: snippet, kind: $0) }
  }
  let keywordMatchKindOrder: [SnippetKeywordMatchKind] = [.keywordExact, .keywordPrefix, .titleOrBody]
  let keywordMatchedSnippetIDs = Set(keywordMatches.map(\.snippet.id))
  return SnippetSearchResult(
    keywordMatches: keywordMatchKindOrder.flatMap { kind in keywordMatches.filter { $0.kind == kind } },
    semanticMatches: try embedder.map { embedder in
      try semanticSnippetMatches(
        query: query,
        snippets: snippets.filter { !keywordMatchedSnippetIDs.contains($0.id) },
        modelContext: modelContext,
        embedder: embedder,
        limit: semanticMatchLimit,
        minimumSimilarity: semanticMatchMinimumSimilarity
      )
    } ?? []
  )
}

/// 文字列の一致で比べるために、大文字と小文字・全角と半角・ひらがなとカタカナの違いをなくす。
///
/// 濁点・半濁点は区別する。`diacriticInsensitive` は濁点も落とし、「かき」で「がぎ」が見つかるため使わない。
func normalizedSnippetSearchText(text: String) -> String {
  let folded = text.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
  return folded.applyingTransform(.hiraganaToKatakana, reverse: true) ?? folded
}

/// スニペットが入力した文字列にどう一致したか。一致しなければ `nil`。
func snippetKeywordMatchKind(snippet: Snippet, normalizedQuery: String) -> SnippetKeywordMatchKind? {
  if let keyword = snippet.keyword.map({ normalizedSnippetSearchText(text: $0) }), !keyword.isEmpty {
    if keyword == normalizedQuery {
      return .keywordExact
    }
    if keyword.hasPrefix(normalizedQuery) {
      return .keywordPrefix
    }
  }
  let normalizedTitleAndBody = normalizedSnippetSearchText(text: [snippet.title, snippet.body].compactMap { $0 }.joined(separator: "\n"))
  return normalizedQuery.split(whereSeparator: \.isWhitespace).allSatisfy { normalizedTitleAndBody.contains($0) } ? .titleOrBody : nil
}

/// `snippets` のうち、クエリと意味が近いものを近い順に最大 `limit` 件返す。コサイン類似度が `minimumSimilarity` 以下のものは返さない。
/// クエリからトークンを取れずベクトルが 0 になった時は、どのスニペットとも比べられないため何も返さない。
func semanticSnippetMatches(
  query: String,
  snippets: [Snippet],
  modelContext: ModelContext,
  embedder: SnippetTextEmbedder,
  limit: Int,
  minimumSimilarity: Float
) throws -> [Snippet] {
  let modelIdentifier = embedder.modelIdentifier
  let embeddingsBySnippetID = Dictionary(
    try modelContext.fetch(FetchDescriptor<SnippetEmbedding>(predicate: #Predicate { $0.modelIdentifier == modelIdentifier }))
      .map { ($0.snippetID, $0) },
    uniquingKeysWith: { first, _ in first }
  )
  let queryVector = l2NormalizedVector(vector: try embedder.vector(query))
  guard queryVector.contains(where: { $0 != 0 }) else {
    return []
  }
  return
    snippets
    .compactMap { snippet -> (snippet: Snippet, similarity: Float)? in
      guard let embedding = embeddingsBySnippetID[snippet.id],
        embedding.sourceHash == snippetEmbeddingSourceHash(sourceText: snippetEmbeddingSourceText(snippet: snippet))
      else {
        return nil
      }
      return (snippet, zip(queryVector, snippetEmbeddingVector(data: embedding.vector)).reduce(0) { $0 + $1.0 * $1.1 })
    }
    .filter { $0.similarity > minimumSimilarity }
    .sorted { $0.similarity > $1.similarity }
    .prefix(limit)
    .map(\.snippet)
}
