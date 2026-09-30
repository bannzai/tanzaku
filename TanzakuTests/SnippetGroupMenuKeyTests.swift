import CoreGraphics
import Testing

@testable import Tanzaku

/// メニューを開いている間のキー入力を、メニューの操作として受け取ってよい修飾キーの状態かを確かめる。
struct SnippetGroupMenuKeyTests {
  @Test(
    "修飾キーを押していない時と、矢印キーが立てるテンキー・Fn の印と Caps Lock だけの時は受け取る",
    // 引数は Sendable でなければならないため、修飾キーは `CGEventFlags` の rawValue で渡す。
    arguments: [0, CGEventFlags([.maskNumericPad, .maskSecondaryFn]).rawValue, CGEventFlags.maskAlphaShift.rawValue] as [UInt64]
  )
  func acceptsKeysWithoutModifiers(modifierFlagsRawValue: UInt64) {
    #expect(isSnippetGroupMenuKeyModifierFree(modifierFlags: CGEventFlags(rawValue: modifierFlagsRawValue)))
  }

  @Test(
    "⇧Return の改行・⌘↑ の文頭への移動のような、修飾キーを押した入力は受け取らない",
    arguments: [
      CGEventFlags.maskShift.rawValue,
      CGEventFlags([.maskCommand, .maskNumericPad, .maskSecondaryFn]).rawValue,
      CGEventFlags.maskAlternate.rawValue,
      CGEventFlags.maskControl.rawValue,
    ] as [UInt64]
  )
  func rejectsKeysWithModifiers(modifierFlagsRawValue: UInt64) {
    #expect(!isSnippetGroupMenuKeyModifierFree(modifierFlags: CGEventFlags(rawValue: modifierFlagsRawValue)))
  }
}
