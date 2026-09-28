import Foundation

/// スニペットの一覧の絞り込み。管理画面・iOS 本体のサイドバーの 1 項目に対応する (`documents/design/Manager.dc.html`)。
public enum SnippetLibraryFilter: Hashable {
  /// すべてのスニペット。
  case allSnippets
  /// MCP クライアント (AI エージェント) が作ったスニペット。
  case addedByAgent
  /// フォルダに入っているスニペット。
  case folder(Folder)
  /// タグを付けたスニペット。
  case tag(Tag)
  /// スニペットグループに入っているスニペット。
  case snippetGroup(SnippetGroup)
}

/// スニペットが絞り込みの条件に当てはまるか。検索の結果を今の絞り込みの中に限るためにも使う。
public func isSnippetInLibraryFilter(snippet: Snippet, filter: SnippetLibraryFilter) -> Bool {
  switch filter {
  case .allSnippets:
    true
  case .addedByAgent:
    snippet.createdByKind == snippetAuthorMCPKind
  case .folder(let folder):
    snippet.folder?.id == folder.id
  case .tag(let tag):
    snippet.tags?.contains { $0.id == tag.id } ?? false
  case .snippetGroup(let snippetGroup):
    snippet.groupItems?.contains { $0.group?.id == snippetGroup.id } ?? false
  }
}

/// 絞り込んだ一覧。スニペットグループはメニューに出す順 (`SnippetGroupItem.sortIndex`) に並べ、それ以外は `snippets` の並びを保つ。
///
/// SwiftData の `#Predicate` は to-many のリレーションの条件を書きにくいため、一覧に出すスニペットを取った後にメモリの上で絞る。
public func filteredLibrarySnippets(snippets: [Snippet], filter: SnippetLibraryFilter) -> [Snippet] {
  if case .snippetGroup(let snippetGroup) = filter {
    return snippetGroupSnippets(snippetGroup: snippetGroup)
  }
  return snippets.filter { isSnippetInLibraryFilter(snippet: $0, filter: filter) }
}
