import TanzakuKit

/// 一覧・確認の画面に出すスニペットの名前。タイトルが無ければ本文の 1 行目にする (`documents/PROJECT.md`「スニペット」)。
func snippetDisplayTitle(snippet: Snippet) -> String {
  if let title = snippet.title, !title.isEmpty {
    return title
  }
  // 空の本文は保存させない (`validateSnippetBody(body:)`) ため、1 行目が無いのは改行だけの本文を検査の前に表示した時だけで、その時は名前を出さない。
  return snippet.body.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
}
