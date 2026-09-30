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
  // 待ち時間は実測していない。アクセシビリティの許可を与えた実機でしか確かめられず、実機の確認は公開前チェックリスト (#4) に移したため。
  Task {
    try? await Task.sleep(for: .milliseconds(100))
    guard !application.isTerminated, NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier else {
      return
    }
    postSyntheticKeyStroke(virtualKey: kVK_ANSI_V, flags: .maskCommand)
  }
}

/// このアプリが送ったキー入力に付ける印 (`CGEventField.eventSourceUserData`)。スニペットグループのキー入力の監視が、自分で送ったバックスペースや ⌘V をユーザーの入力として数えないために使う。
///
/// ほかのアプリが同じ値を付けることは想定しない。値はグローバルショートカットの識別子 (`GlobalHotKey.swift`) と同じ "TNZK" の 4 文字。
let syntheticKeyEventUserData: Int64 = 0x544E_5A4B

/// キーを 1 回押して離すイベントを前面のアプリへ送る。アクセシビリティ (イベント送信) の許可が無いとイベントは届かない。
///
/// 冪等ではない: 呼ぶたびにキー入力が 1 回起きる。
/// 押している修飾キーを引き継がないよう、`flags` で修飾キーを必ず上書きする。
func postSyntheticKeyStroke(virtualKey: Int, flags: CGEventFlags) {
  let eventSource = CGEventSource(stateID: .combinedSessionState)
  for isKeyDown in [true, false] {
    let event = CGEvent(keyboardEventSource: eventSource, virtualKey: CGKeyCode(virtualKey), keyDown: isKeyDown)
    event?.flags = flags
    event?.setIntegerValueField(.eventSourceUserData, value: syntheticKeyEventUserData)
    event?.post(tap: .cghidEventTap)
  }
}
