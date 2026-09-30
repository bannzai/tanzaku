import ApplicationServices

/// アクセシビリティ API の問い合わせを待つ上限 (秒)。問い合わせは応答しないアプリを既定で 6 秒待ち、その間メインスレッド (キー入力の監視を含む) が止まるため、メニューを出すのが遅れたと感じない長さに縮める。
private let focusedTextCaretMessagingTimeout: Float = 0.25

/// 前面のアプリのフォーカスがある入力欄のキャレットの矩形 (Quartz の座標。原点は主画面の左上)。取れなければ `nil`。
///
/// フォーカスがある要素の選択範囲 (`kAXSelectedTextRangeAttribute`) の先頭の位置の矩形 (`kAXBoundsForRangeParameterizedAttribute`) を取る。
/// 長さ 0 の範囲の矩形を返さない (大きさ 0 を返す) アプリがあるため、その時は直前の 1 文字の矩形を取り、その右端をキャレットにする。
/// アクセシビリティの許可が無い・入力欄でない・アプリが対応していない時は `nil` を返し、呼び出し側はマウスポインタの位置に出す。
func focusedTextCaretRect() -> CGRect? {
  let systemWideElement = AXUIElementCreateSystemWide()
  // システム全体の要素に設定すると、すべての要素の問い合わせの上限になる。
  AXUIElementSetMessagingTimeout(systemWideElement, focusedTextCaretMessagingTimeout)
  guard let focusedElement = accessibilityAttributeValue(element: systemWideElement, attribute: kAXFocusedUIElementAttribute as CFString),
    CFGetTypeID(focusedElement) == AXUIElementGetTypeID()
  else {
    return nil
  }
  let element = focusedElement as! AXUIElement
  guard let selectedTextRangeValue = accessibilityAttributeValue(element: element, attribute: kAXSelectedTextRangeAttribute as CFString),
    CFGetTypeID(selectedTextRangeValue) == AXValueGetTypeID()
  else {
    return nil
  }
  var selectedTextRange = CFRange()
  guard AXValueGetValue(selectedTextRangeValue as! AXValue, .cfRange, &selectedTextRange) else {
    return nil
  }
  if let caretRect = textBoundsRect(element: element, range: CFRange(location: selectedTextRange.location, length: 0)), caretRect.height > 0 {
    return caretRect
  }
  guard selectedTextRange.location > 0,
    let previousCharacterRect = textBoundsRect(element: element, range: CFRange(location: selectedTextRange.location - 1, length: 1)),
    previousCharacterRect.height > 0
  else {
    return nil
  }
  return CGRect(x: previousCharacterRect.maxX, y: previousCharacterRect.minY, width: 0, height: previousCharacterRect.height)
}

/// 要素の属性の値。取れなければ `nil`。
private func accessibilityAttributeValue(element: AXUIElement, attribute: CFString) -> CFTypeRef? {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
    return nil
  }
  return value
}

/// 入力欄の文字の範囲 `range` の矩形 (Quartz の座標)。取れなければ `nil`。
private func textBoundsRect(element: AXUIElement, range: CFRange) -> CGRect? {
  var mutableRange = range
  guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else {
    return nil
  }
  var boundsValue: CFTypeRef?
  guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &boundsValue) == .success,
    let boundsValue,
    CFGetTypeID(boundsValue) == AXValueGetTypeID()
  else {
    return nil
  }
  var bounds = CGRect.zero
  guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &bounds) else {
    return nil
  }
  return bounds
}
