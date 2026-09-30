import Foundation
import SwiftData

/// iOS 本体のサイドバーでスニペットグループを選んだ時の一覧に出すスニペット。検索欄が空ならメニューに並べる順、入力があればグループの中の検索の結果を返す。
///
/// 検索の結果の並びと意味検索の件数の上限は `filteredSnippets(query:filter:snippets:modelContext:embedder:)` と同じで、意味検索はグループの中から選ぶ。
/// スニペットグループは `SnippetLibraryFilter` の絞り込みに無いため (Mac の管理ウィンドウはグループを一覧と編集で扱う)、グループのスニペットを渡して絞り込み「すべて」で検索し、文字列で一致したもののうちグループの外のものを除く。
public func filteredSnippetGroupSnippets(
  query: String,
  snippetGroup: SnippetGroup,
  modelContext: ModelContext,
  embedder: SnippetTextEmbedder?
) throws -> [Snippet] {
  let groupSnippets = sortedSnippetGroupItems(snippetGroup: snippetGroup).compactMap(\.snippet)
  let groupSnippetIDs = Set(groupSnippets.map(\.id))
  return try filteredSnippets(query: query, filter: .all, snippets: groupSnippets, modelContext: modelContext, embedder: embedder)
    .filter { groupSnippetIDs.contains($0.id) }
}
