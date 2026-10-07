import Foundation

/// 打った文字の末尾がキーワードと一致した、その場で本文に置き換えるスニペット。置き換えるものが無ければ `nil`。
///
/// キーワードは打った文字列をそのまま照合する (大文字と小文字を区別した完全一致。`documents/DIRECTION.md`「決めたこと」)。
/// 片方のキーワードがもう片方の末尾になっている時 (`env` と `;dev-env` など) は長い方を選ぶ。長い方を打った時に短い方の本文に置き換えないため。
/// スニペットグループのキーワードの方が長く一致している時は `nil` を返し、グループのメニュー (`snippetGroupMatchingTypedText(typedText:snippetGroups:)`) に任せる。
/// キーワードはスニペットとスニペットグループで共通の名前空間で一意 (`validateKeywordIsUnique(keyword:ownerID:modelContext:)`) のため、同じ長さで両方が一致することは無い。
public func snippetMatchingTypedText(typedText: String, snippets: [Snippet], snippetGroups: [SnippetGroup]) -> Snippet? {
  guard
    let snippet =
      snippets
      .filter({ snippet in
        guard let keyword = snippet.keyword, !keyword.isEmpty else {
          return false
        }
        return typedText.hasSuffix(keyword)
      })
      .max(by: { ($0.keyword ?? "").count < ($1.keyword ?? "").count })
  else {
    return nil
  }
  let snippetGroupKeywordCount = (snippetGroupMatchingTypedText(typedText: typedText, snippetGroups: snippetGroups)?.keyword ?? "").count
  return (snippet.keyword ?? "").count > snippetGroupKeywordCount ? snippet : nil
}

/// スニペットのキーワードを本文に置き換える前に、打ったキーワードを消すために送るバックスペースの数。
///
/// キーワードの最後の文字のキー入力は入力欄へ渡さずに置き換えるため、入力欄に入っているのは最後の 1 文字を除いた分になる。
/// 最後のキー入力を渡してから消すと、渡したキー入力と送ったバックスペースのどちらが先に入力欄へ届くかを保証できないため。
public func snippetKeywordBackspaceCount(keyword: String) -> Int {
  max(snippetGroupKeywordBackspaceCount(keyword: keyword) - 1, 0)
}
