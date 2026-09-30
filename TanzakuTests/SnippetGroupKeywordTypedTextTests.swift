import Carbon.HIToolbox
import CoreGraphics
import Testing

@testable import Tanzaku

/// キー入力 1 回を受けた後の、キーワードの判定に使う直前に打った文字を確かめる。
struct SnippetGroupKeywordTypedTextTests {
  @Test("文字のキー入力は末尾に足し、最も長いキーワードの文字数だけを残す")
  func appendsCharactersAndKeepsSuffix() {
    #expect(snippetGroupKeywordTypedText(typedText: ";focus-ap", keyCode: kVK_ANSI_P, modifierFlags: [], characters: "p", maxLength: 10) == ";focus-app")
    #expect(snippetGroupKeywordTypedText(typedText: "echo ;dev", keyCode: kVK_ANSI_V, modifierFlags: [], characters: "v", maxLength: 5) == ";devv")
    #expect(snippetGroupKeywordTypedText(typedText: ";DEV", keyCode: kVK_ANSI_X, modifierFlags: .maskShift, characters: "X", maxLength: 10) == ";DEVX")
  }

  @Test("キーワードを持つグループが無い (最も長いキーワードの文字数が 0) 時は何も残さない")
  func keepsNothingWithoutKeywords() {
    #expect(snippetGroupKeywordTypedText(typedText: "", keyCode: kVK_ANSI_A, modifierFlags: [], characters: "a", maxLength: 0) == "")
  }

  @Test("バックスペースは最後の 1 文字を消し、⌥ を押した単語の削除では空にする")
  func backspaceRemovesLastCharacter() {
    #expect(snippetGroupKeywordTypedText(typedText: ";focus-appx", keyCode: kVK_Delete, modifierFlags: [], characters: "\u{7F}", maxLength: 10) == ";focus-app")
    #expect(snippetGroupKeywordTypedText(typedText: "", keyCode: kVK_Delete, modifierFlags: [], characters: "\u{7F}", maxLength: 10) == "")
    #expect(snippetGroupKeywordTypedText(typedText: ";focus-app", keyCode: kVK_Delete, modifierFlags: .maskAlternate, characters: "\u{7F}", maxLength: 10) == "")
  }

  @Test(
    "⌘・⌃ の組み合わせと、Return・Tab・Esc・矢印・前方への削除は空にする",
    // 引数は Sendable でなければならないため、修飾キーは `CGEventFlags` の rawValue で渡す。
    arguments: [
      (kVK_ANSI_V, CGEventFlags.maskCommand.rawValue, "v"),
      (kVK_ANSI_A, CGEventFlags.maskControl.rawValue, "\u{01}"),
      (kVK_Return, 0, "\r"),
      (kVK_Tab, 0, "\t"),
      (kVK_Escape, 0, "\u{1B}"),
      (kVK_LeftArrow, CGEventFlags.maskNumericPad.rawValue, "\u{F702}"),
      (kVK_ForwardDelete, 0, "\u{F728}"),
      (kVK_ANSI_A, 0, ""),
    ] as [(Int, UInt64, String)]
  )
  func resetsOnNonTypingKeys(keyCode: Int, modifierFlagsRawValue: UInt64, characters: String) {
    #expect(
      snippetGroupKeywordTypedText(
        typedText: ";focus-ap",
        keyCode: keyCode,
        modifierFlags: CGEventFlags(rawValue: modifierFlagsRawValue),
        characters: characters,
        maxLength: 10
      ) == ""
    )
  }
}
