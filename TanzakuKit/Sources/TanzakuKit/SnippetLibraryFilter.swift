import Foundation
import SwiftData

/// スニペットの一覧の絞り込み。Mac の管理ウィンドウのサイドバー (`documents/design/Manager.dc.html`) と iOS 本体の絞り込みで選ぶ。
///
/// フォルダ・タグはモデルではなく `id` で持つ。選択の状態として保持・比較 (`Hashable`) するため。
public enum SnippetLibraryFilter: Hashable, Sendable {
  /// すべてのスニペット。
  case all
  /// MCP クライアント (AI エージェント) が作成したスニペット。
  case addedByAgent
  /// フォルダに入っているスニペット。
  case folder(folderID: UUID)
  /// タグを付けたスニペット。
  case tag(tagID: UUID)
}

/// スニペットが絞り込みの条件に合うか。
///
/// 「AI エージェントが追加」は作成した主体だけで判定する。ユーザーが作って AI エージェントが更新したものは「追加」ではないため。
public func snippetMatchesLibraryFilter(snippet: Snippet, filter: SnippetLibraryFilter) -> Bool {
  switch filter {
  case .all:
    true
  case .addedByAgent:
    snippet.createdByKind == "mcp"
  case .folder(let folderID):
    snippet.folder?.id == folderID
  case .tag(let tagID):
    (snippet.tags ?? []).contains { $0.id == tagID }
  }
}

/// 管理画面の一覧に出す、絞り込みに合うスニペット。検索欄が空なら `snippets` の並びのまま、入力があれば検索の結果を返す。
///
/// `snippets` には一覧の既定の並び (更新日時の新しい順) のすべてのスニペットを渡す。画面では `@Query` の結果を渡し、スニペットの追加・更新・削除で一覧を描き直させるため。
/// 検索の結果は、文字列で一致したもの (`searchSnippets(query:modelContext:embedder:)` の並び) の後に、意味検索で見つかったものを続ける。管理画面の一覧は 1 列で、検索の並び (一致の強い順) をそのまま使うため。
/// 意味検索は絞り込みに合うスニペットの中から件数の上限まで選ぶ。全体から選んだ上位を後から絞り込むと、絞り込みの中に意味の近いものがあっても上位に入らず出なくなるため。
public func filteredSnippets(
  query: String,
  filter: SnippetLibraryFilter,
  snippets: [Snippet],
  modelContext: ModelContext,
  embedder: SnippetTextEmbedder?
) throws -> [Snippet] {
  let librarySnippets = snippets.filter { snippetMatchesLibraryFilter(snippet: $0, filter: filter) }
  guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
    return librarySnippets
  }
  let keywordMatchedSnippets = try searchSnippets(query: query, modelContext: modelContext, embedder: nil).keywordMatches
    .map(\.snippet)
    .filter { snippetMatchesLibraryFilter(snippet: $0, filter: filter) }
  guard let embedder else {
    return keywordMatchedSnippets
  }
  let keywordMatchedSnippetIDs = Set(keywordMatchedSnippets.map(\.id))
  return keywordMatchedSnippets
    + (try semanticSnippetMatches(
      query: query,
      snippets: librarySnippets.filter { !keywordMatchedSnippetIDs.contains($0.id) },
      modelContext: modelContext,
      embedder: embedder,
      limit: semanticMatchLimit,
      minimumSimilarity: semanticMatchMinimumSimilarity
    ))
}
