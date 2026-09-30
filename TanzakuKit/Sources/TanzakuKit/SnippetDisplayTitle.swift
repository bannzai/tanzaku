import Foundation

/// 一覧・ランチャー・スニペットグループのメニューに出すスニペットの名前。タイトルが無いスニペットは本文の 1 行目で代える (`documents/DIRECTION.md`「決めたこと」)。
///
/// 空白だけのタイトルは名前にならないため、タイトルが無いものとして扱う。本文の先頭の空行も名前にならないため飛ばす。
public func snippetDisplayTitle(snippet: Snippet) -> String {
  if let title = snippet.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
    return title
  }
  return snippetBodyFirstLine(body: snippet.body)
}

/// 本文の最初の空でない行。ランチャーの結果の行に本文の書き出しを 1 行だけ出すためと、タイトルが無い時の名前に使う。
public func snippetBodyFirstLine(body: String) -> String {
  body.split(whereSeparator: \.isNewline)
    .lazy
    .map { $0.trimmingCharacters(in: .whitespaces) }
    .first { !$0.isEmpty } ?? ""
}
