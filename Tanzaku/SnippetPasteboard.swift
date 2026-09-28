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
/// ⌘V は送った時点の前面のアプリに届くため、送る直前に `application` が終了しておらず前面にあることを確かめ、違えば送らない (コピーだけで終える)。待つ間にユーザーが別のアプリへ切り替えた時に、本文を意図しない入力欄へ貼り付けないため。
/// 冪等ではない: 呼ぶたびに貼り付けが 1 回起きる。
func pasteToApplication(application: NSRunningApplication?) {
  guard let application else {
    return
  }
  application.activate()
  // 前面に戻したアプリがキーウィンドウを取り戻してから ⌘V を受け取るよう、少し待ってから送る。
  // 待ち時間は実測していない。App Sandbox の中ではアクセシビリティの許可を得られず確かめられないため (App Sandbox を外す #7 の後に実機で確かめる)。
  Task {
    try? await Task.sleep(for: .milliseconds(100))
    guard !application.isTerminated, NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier else {
      return
    }
    let eventSource = CGEventSource(stateID: .combinedSessionState)
    for isKeyDown in [true, false] {
      let event = CGEvent(keyboardEventSource: eventSource, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: isKeyDown)
      event?.flags = .maskCommand
      event?.post(tap: .cghidEventTap)
    }
  }
}
