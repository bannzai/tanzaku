import AppKit
import Carbon.HIToolbox

/// スニペットの本文をクリップボードに入れる。同じ本文で何度呼んでもクリップボードの中身は同じになる。
func copySnippetBodyToPasteboard(body: String) {
  NSPasteboard.general.clearContents()
  NSPasteboard.general.setString(body, forType: .string)
}

/// アクセシビリティの許可があるか。⌘V のイベントを別のアプリへ送るのに要る。
func isAccessibilityTrusted() -> Bool {
  AXIsProcessTrusted()
}

/// `application` を前面に戻し、⌘V を送ってクリップボードの中身を貼り付ける。アクセシビリティの許可が無いとイベントは届かないため、呼ぶ前に `isAccessibilityTrusted()` を確かめる。
///
/// 冪等ではない: 呼ぶたびに貼り付けが 1 回起きる。
func pasteToApplication(application: NSRunningApplication?) {
  application?.activate()
  // 前面に戻したアプリがキーウィンドウを取り戻してから ⌘V を受け取るよう、少し待ってから送る。
  // 待ち時間は実測していない。App Sandbox の中ではアクセシビリティの許可を得られず確かめられないため (App Sandbox を外す #7 の後に実機で確かめる)。
  DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
    let eventSource = CGEventSource(stateID: .combinedSessionState)
    for isKeyDown in [true, false] {
      let event = CGEvent(keyboardEventSource: eventSource, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: isKeyDown)
      event?.flags = .maskCommand
      event?.post(tap: .cghidEventTap)
    }
  }
}
