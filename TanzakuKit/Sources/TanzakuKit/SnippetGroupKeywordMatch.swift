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

/// iOS のカスタムキーボードでメニューを出すスニペットグループ。出さない時は `nil`。
///
/// `documentContextBeforeInput` は入力欄のカーソルより前の文字 (`UITextDocumentProxy.documentContextBeforeInput`)。Mac のようにキー入力を積み上げず、入力欄の文字で判定する。キーボードは入力欄の文字を読めるため、カーソルを動かした後や別のキーボードで打った後も正しく判定できる。
/// `dismissedDocumentContextBeforeInput` はメニューを閉じた時のカーソルより前の文字。閉じてもキーワードは入力欄に残るため、同じ文字の間は出し直さない。続けて打つかカーソルを動かすと文字が変わり、また判定する。
public func snippetGroupMatchingDocumentContext(
  documentContextBeforeInput: String?,
  dismissedDocumentContextBeforeInput: String?,
  snippetGroups: [SnippetGroup]
) -> SnippetGroup? {
  guard let documentContextBeforeInput, documentContextBeforeInput != dismissedDocumentContextBeforeInput else {
    return nil
  }
  return snippetGroupMatchingTypedText(typedText: documentContextBeforeInput, snippetGroups: snippetGroups)
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
