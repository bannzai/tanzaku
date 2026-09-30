import Carbon.HIToolbox
import CoreGraphics

/// キー入力 1 回を受けた後の、キーワードの判定に使う直前に打った文字。
///
/// 打った文字はキーワードの判定だけに使い、保存・ログ出力・送信をしない (`documents/PROJECT.md`「スニペットグループとキーワード展開」)。そのため末尾の `maxLength` 文字 (最も長いキーワードの文字数) だけを残す。
/// 入力欄のどこに打ったかをキー入力からは追えないため、キャレットを動かし得る入力 (⌘・⌃ の組み合わせ、Return・Tab・矢印などの文字にならないキー、⌥ を押したバックスペースの単語の削除、前方への削除) では空にする。
/// バックスペースだけは入力欄の末尾の 1 文字を消すため、最後の 1 文字を消して続ける。キーワードを打ち間違えて直した時もメニューを出すため。
/// `characters` はキー入力が作る文字 (`CGEvent.keyboardGetUnicodeString`)。日本語の入力の変換中は変換前のキーの文字になるため、キーワードは英数字の入力で打った時だけ一致する。
func snippetGroupKeywordTypedText(typedText: String, keyCode: Int, modifierFlags: CGEventFlags, characters: String, maxLength: Int) -> String {
  if !modifierFlags.isDisjoint(with: [.maskCommand, .maskControl]) {
    return ""
  }
  if keyCode == kVK_Delete {
    return modifierFlags.contains(.maskAlternate) ? "" : String(typedText.dropLast())
  }
  // 矢印・ファンクションキーの文字は Unicode の私用領域 (NSUpArrowFunctionKey など)、Return・Tab・Esc・前方への削除は制御文字になる。
  guard !characters.isEmpty, characters.unicodeScalars.allSatisfy({ ![.control, .privateUse].contains($0.properties.generalCategory) }) else {
    return ""
  }
  return String((typedText + characters).suffix(maxLength))
}
