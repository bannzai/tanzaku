import CoreGraphics

/// メニューを開いている間のキー入力を、メニューの操作 (↑↓・Return・Esc) として受け取ってよい修飾キーの状態か。
///
/// ⇧・⌘・⌥・⌃ を押している時は受け取らず、入力欄へ渡す。⇧Return の改行や ⌘↑ の文頭への移動のような入力欄の操作を奪わないため。
/// 矢印キーが立てるテンキーと Fn の印 (`maskNumericPad`・`maskSecondaryFn`) と Caps Lock は、押している修飾キーではないため見ない。
func isSnippetGroupMenuKeyModifierFree(modifierFlags: CGEventFlags) -> Bool {
  modifierFlags.isDisjoint(with: [.maskShift, .maskCommand, .maskAlternate, .maskControl])
}
