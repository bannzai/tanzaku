import Foundation

/// 打った文字の末尾がキーワードと一致した、メニューを出すスニペットグループ。一致するものが無ければ `nil`。
///
/// キーワードは打った文字列をそのまま照合する (大文字と小文字を区別した完全一致。`documents/DIRECTION.md`「決めたこと」)。
/// 片方のキーワードがもう片方の末尾になっている時 (`;env` と `;dev-env` など) は長い方を選ぶ。長い方を打った時に短い方のメニューを出さないため。
/// メニューに並べるスニペットが無いグループは、出しても選べるものが無いため選ばない。
public func snippetGroupMatchingTypedText(typedText: String, snippetGroups: [SnippetGroup]) -> SnippetGroup? {
  snippetGroups
    .filter { snippetGroup in
      guard let keyword = snippetGroup.keyword, !keyword.isEmpty else {
        return false
      }
      return typedText.hasSuffix(keyword) && !snippetGroupMenuSnippets(snippetGroup: snippetGroup).isEmpty
    }
    .max { ($0.keyword ?? "").count < ($1.keyword ?? "").count }
}

/// スニペットグループのメニューに並べるスニペット。メニューの並び順で、消されたスニペットの項目は除く。
public func snippetGroupMenuSnippets(snippetGroup: SnippetGroup) -> [Snippet] {
  sortedSnippetGroupItems(snippetGroup: snippetGroup).compactMap(\.snippet)
}

/// メニューで選んだ本文を入れる前に、打ったキーワードを消すために送るバックスペースの数。
///
/// バックスペースは 1 回で 1 文字 (書記素クラスタ) を消すため、`String.count` の文字数にする。
/// キーワードの判定はキー入力 1 回で入った文字を積み上げて行うため、キーワードを打ったキー入力の回数とも一致する。
public func snippetGroupKeywordBackspaceCount(keyword: String) -> Int {
  keyword.count
}
