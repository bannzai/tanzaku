import AppKit
import ApplicationServices
import SwiftData
import TanzakuKit

/// 入力監視の許可があるか。ほかのアプリへのキー入力を見てキーワードを判定するのに要る。
func isInputMonitoringAllowed() -> Bool {
  CGPreflightListenEventAccess()
}

/// アクセシビリティの許可 (イベント送信を含む) があるか。キャレットの位置を取る・メニューを開いている間の ↑↓・Return・Esc を入力欄へ渡さずに受け取る・キーワードを消すバックスペースと ⌘V を送るのに要る。
func isSnippetGroupAccessibilityAllowed() -> Bool {
  isSyntheticKeyStrokeAllowed()
}

/// キーワード展開 (スニペットのキーワードの置き換えとスニペットグループのメニュー) に要る許可がすべてあるか。1 つでも欠けたらキー入力の監視を始めない (`documents/PROJECT.md`「スニペットグループとキーワード展開」)。
func isSnippetGroupKeywordExpansionAllowed() -> Bool {
  isInputMonitoringAllowed() && isSnippetGroupAccessibilityAllowed()
}

/// アクセシビリティの一覧でオンにした (`AXIsProcessTrusted()` が true) のに、キーワード展開に要るアクセシビリティの許可 (`isSnippetGroupAccessibilityAllowed()`) が無いか。
///
/// イベント送信の許可 (`CGPreflightPostEventAccess`) は実行中に許可しても値が変わらず、開き直すと変わる。Apple の DTS も、システム設定がアプリの終了と開き直しを勧めるのはこのためと答えている ( https://developer.apple.com/forums/thread/727984 )。`AXIsProcessTrusted()` は実行中の変化を返す (Rectangle は値の変化を待って先へ進む: https://github.com/rxhanson/Rectangle/blob/main/Rectangle/AccessibilityAuthorization/AccessibilityAuthorization.swift )。
func isKeywordPermissionRelaunchNeeded() -> Bool {
  isAccessibilityTrusted() && !isSnippetGroupAccessibilityAllowed()
}

/// キーワード展開の許可のウィンドウを出すか。許可がすべてあれば出さない。キーワードを持つスニペットもスニペットグループも無い時は、キーワードを使わない人に起動のたびに出さないため出さない (`documents/DIRECTION.md`「決めたこと」の 2026-10-17 の行)。
///
/// キーワードは保存する時に空を `nil` に寄せる (`applySnippetEdit`・`applySnippetGroupEdit`・MCP の `mcpOptionalText`) ため、`nil` でないものを数える。
func isKeywordPermissionWindowNeeded(isKeywordExpansionAllowed: Bool, modelContext: ModelContext) throws -> Bool {
  guard !isKeywordExpansionAllowed else {
    return false
  }
  return try modelContext.fetchCount(FetchDescriptor<Snippet>(predicate: #Predicate { $0.keyword != nil })) > 0
    || modelContext.fetchCount(FetchDescriptor<SnippetGroup>(predicate: #Predicate { $0.keyword != nil })) > 0
}

/// このアプリを終了して開き直す。終了を待ってから開くため、古いプロセスのキー入力の監視と新しいプロセスの監視が重ならない。
///
/// `NSWorkspace.openApplication` は起動中の自分を前に出すだけで新しいプロセスを作らないため、終了を待つシェルに開かせる。
/// 冪等ではない: 呼ぶたびにアプリが終了する。
func relaunchApplication() {
  let process = Process()
  process.executableURL = URL(filePath: "/bin/sh")
  process.arguments = [
    "-c",
    "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$2\"",
    "sh",
    String(ProcessInfo.processInfo.processIdentifier),
    Bundle.main.bundleURL.path(percentEncoded: false),
  ]
  do {
    try process.run()
  } catch {
    // 開き直せないまま終了すると、ユーザーが自分で開くまでランチャーもキーワード展開も使えないため、終了しない。
    return
  }
  NSApp.terminate(nil)
}

/// 入力監視の許可を求めてシステム設定の「入力監視」を開く。
///
/// 許可を求めるダイアログは初めて求めた時だけ出る。起動時に呼ぶと `make test` (アプリを起動して走る) の CI でダイアログが出たままになるため、ユーザーが案内のボタンを押した時だけ呼ぶ。
func requestInputMonitoringAccess() {
  CGRequestListenEventAccess()
  openPrivacySettings(anchor: "Privacy_ListenEvent")
}

/// システム設定の「プライバシーとセキュリティ」の `anchor` の項目を開く。
private func openPrivacySettings(anchor: String) {
  if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
    NSWorkspace.shared.open(url)
  }
}
