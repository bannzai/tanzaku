import TanzakuKit

/// 一覧・確認の画面に出すスニペットの名前。タイトルが無ければ本文の 1 行目にする (`documents/PROJECT.md`「スニペット」)。
func snippetDisplayTitle(snippet: Snippet) -> String {
  if let title = snippet.title, !title.isEmpty {
    return title
  }
  return snippet.body.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
}
