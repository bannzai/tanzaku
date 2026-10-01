import Foundation
import SwiftData

/// App Intents (ショートカット・アクションボタン) でスニペットを扱えなかった理由。`description` はショートカットの画面にそのまま表示する。
public enum SnippetIntentError: Error, Equatable, CustomStringConvertible, LocalizedError {
  /// 選んだスニペットがストアに無い (ショートカットに保存した後に消された)。
  case snippetNotFound(snippetID: UUID)

  /// ショートカットはエラーの `localizedDescription` を表示するため、`description` をそのまま返す。
  public var errorDescription: String? {
    description
  }

  /// 画面にそのまま表示する文言。アプリと拡張のどこから表示しても同じ翻訳になるよう、このパッケージの翻訳を使う。
  public var description: String {
    switch self {
    case .snippetNotFound:
      String(localized: "The snippet was not found. It may have been deleted.", bundle: .module)
    }
  }
}

/// App Intents でスニペットを選ぶ時の検索の結果。
///
/// ショートカットの選択肢は 1 列のため、`searchSnippets` の文字列の一致と意味検索の結果をこの順に 1 列に並べる。
public func snippetIntentSearchResults(query: String, modelContext: ModelContext, embedder: SnippetTextEmbedder?) throws -> [Snippet] {
  let searchResult = try searchSnippets(query: query, modelContext: modelContext, embedder: embedder)
  return searchResult.keywordMatches.map(\.snippet) + searchResult.semanticMatches
}

/// App Intents で選んだスニペットの本文を `pasteboardWriter` でクリップボードへ入れ、使った日時を `usedAt` にして、そのスニペットを返す。無ければ `SnippetIntentError.snippetNotFound` を投げる。
///
/// クリップボードへの書き込みを引数で受け取るのは、クリップボードを使わないテストで入れる本文を確かめるため。同じスニペットと `usedAt` で何度呼んでもクリップボードの中身と使った日時は同じになる。
/// 使った日時の保存に失敗してもエラーにしない。コピーは済んでおり、最近使ったスニペットに出ないだけのため。
public func copySnippetBody(snippetID: UUID, modelContext: ModelContext, usedAt: Date, pasteboardWriter: (String) -> Void) throws -> Snippet {
  guard let snippet = try modelContext.fetch(FetchDescriptor<Snippet>(predicate: #Predicate { $0.id == snippetID })).first else {
    throw SnippetIntentError.snippetNotFound(snippetID: snippetID)
  }
  pasteboardWriter(snippet.body)
  try? recordSnippetUse(snippet: snippet, usedAt: usedAt, modelContext: modelContext)
  return snippet
}
