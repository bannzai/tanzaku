import AppKit
import ApplicationServices

/// 入力監視の許可があるか。ほかのアプリへのキー入力を見てキーワードを判定するのに要る。
func isInputMonitoringAllowed() -> Bool {
  CGPreflightListenEventAccess()
}

/// アクセシビリティの許可 (イベント送信を含む) があるか。キャレットの位置を取る・メニューを開いている間の ↑↓・Return・Esc を入力欄へ渡さずに受け取る・キーワードを消すバックスペースと ⌘V を送るのに要る。
///
/// イベント送信の許可はシステム設定の「アクセシビリティ」の一覧で与えるため、アクセシビリティと 1 つにまとめて扱う。
func isSnippetGroupAccessibilityAllowed() -> Bool {
  isAccessibilityTrusted() && CGPreflightPostEventAccess()
}

/// スニペットグループのメニューに要る許可がすべてあるか。1 つでも欠けたらキー入力の監視を始めない (`documents/PROJECT.md`「スニペットグループとキーワード展開」)。
func isSnippetGroupKeywordExpansionAllowed() -> Bool {
  isInputMonitoringAllowed() && isSnippetGroupAccessibilityAllowed()
}

/// 入力監視の許可を求めてシステム設定の「入力監視」を開く。
///
/// 許可を求めるダイアログは初めて求めた時だけ出る。起動時に呼ぶと `make test` (アプリを起動して走る) の CI でダイアログが出たままになるため、ユーザーが案内のボタンを押した時だけ呼ぶ。
func requestInputMonitoringAccess() {
  CGRequestListenEventAccess()
  openPrivacySettings(anchor: "Privacy_ListenEvent")
}

/// アクセシビリティとイベント送信の許可を求めてシステム設定の「アクセシビリティ」を開く。呼ぶ場面は `requestInputMonitoringAccess()` と同じ。
func requestSnippetGroupAccessibilityAccess() {
  // キーは `kAXTrustedCheckOptionPrompt` の値。SDK の版で Swift への取り込み方 (`Unmanaged` か否か) が変わるため、文字列で渡す。
  AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
  CGRequestPostEventAccess()
  openPrivacySettings(anchor: "Privacy_Accessibility")
}

/// システム設定の「プライバシーとセキュリティ」の `anchor` の項目を開く。
private func openPrivacySettings(anchor: String) {
  if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
    NSWorkspace.shared.open(url)
  }
}
