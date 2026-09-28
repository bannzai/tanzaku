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

/// 管理画面の一覧に出すスニペット。検索欄が空なら `snippets`、入力があれば `searchSnippets(query:modelContext:embedder:)` の結果を、絞り込みに合うものだけにして返す。
///
/// `snippets` には一覧の既定の並び (更新日時の新しい順) のすべてのスニペットを渡す。画面では `@Query` の結果を渡し、スニペットの追加・更新・削除で一覧を描き直させるため、ここではストアから読み直さない。
/// 検索の結果は、文字列で一致したものの後に意味検索で見つかったものを続ける。管理画面の一覧は 1 列で、検索の並び (一致の強い順) をそのまま使うため。
public func filteredSnippets(
  query: String,
  filter: SnippetLibraryFilter,
  snippets: [Snippet],
  modelContext: ModelContext,
  embedder: SnippetTextEmbedder?
) throws -> [Snippet] {
  guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
    return snippets.filter { snippetMatchesLibraryFilter(snippet: $0, filter: filter) }
  }
  let searchResult = try searchSnippets(query: query, modelContext: modelContext, embedder: embedder)
  return (searchResult.keywordMatches.map(\.snippet) + searchResult.semanticMatches).filter { snippetMatchesLibraryFilter(snippet: $0, filter: filter) }
}
