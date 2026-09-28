import Foundation

/// 一覧・ランチャー・スニペットグループのメニューに出すスニペットの名前。タイトルが無ければ本文の 1 行目を出す (`documents/DIRECTION.md`「決めたこと」)。
///
/// 空白だけのタイトルと、本文の先頭の空白だけの行は、表示しても何も読めないため飛ばす。
public func snippetDisplayTitle(snippet: Snippet) -> String {
  if let title = snippet.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    return title
  }
  return snippet.body
    .split(whereSeparator: \.isNewline)
    .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    .map(String.init) ?? ""
}
