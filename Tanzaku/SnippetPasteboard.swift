import AppKit
import Carbon.HIToolbox
import TanzakuKit
import os

/// クリップボードに入れる添付のファイルの書き出しの失敗の記録。添付の中身とファイル名は入れない (`.claude/rules/snippet-content-handling.md`)。
private let snippetPasteboardLogger = Logger(subsystem: "com.bannzai.tanzaku", category: "SnippetPasteboard")

/// スニペットの中身 (本文か添付) をクリップボードに入れる (`copySnippetContentToPasteboard`)。
func copySnippetToPasteboard(snippet: Snippet) {
  copySnippetContentToPasteboard(
    snippetID: snippet.id,
    body: snippet.body,
    attachmentData: snippet.attachmentData,
    attachmentContentType: snippet.attachmentContentType,
    attachmentFileName: snippet.attachmentFileName
  )
}

/// スニペットの中身をクリップボードに入れる。添付があれば添付、無ければ本文を入れる。同じ中身で何度呼んでもクリップボードの中身は同じになる。
///
/// 添付はデータをその種類 (UTType) のまま入れ、同じ項目にファイルの URL も入れる。画像のデータを受け取るアプリ (メモ・プレビューなど) と、
/// ファイルとして受け取るアプリ (Finder・チャットの添付など) のどちらにも貼れるようにするため。動画のデータを直接受け取るアプリは少なく、ファイルの URL が主な受け渡しになる。
/// ファイルはアプリのキャッシュの `SnippetAttachments/<スニペットの識別子>/` に書き出し、同じスニペットは同じ場所に上書きする。書き出せなかった時はデータだけを入れる。
func copySnippetContentToPasteboard(snippetID: UUID, body: String, attachmentData: Data?, attachmentContentType: String?, attachmentFileName: String?) {
  NSPasteboard.general.clearContents()
  guard let attachmentData, let attachmentContentType else {
    NSPasteboard.general.setString(body, forType: .string)
    return
  }
  let pasteboardItem = NSPasteboardItem()
  pasteboardItem.setData(attachmentData, forType: NSPasteboard.PasteboardType(attachmentContentType))
  do {
    let attachmentFileURL = try writeSnippetAttachmentFile(
      snippetID: snippetID,
      attachmentData: attachmentData,
      attachmentFileName: snippetAttachmentFileName(originalFileName: attachmentFileName, contentType: attachmentContentType)
    )
    pasteboardItem.setString(attachmentFileURL.absoluteString, forType: .fileURL)
  } catch {
    snippetPasteboardLogger.error("Failed to write the attachment file: \(String(describing: type(of: error)), privacy: .public)")
  }
  NSPasteboard.general.writeObjects([pasteboardItem])
}

/// 添付をクリップボードに入れるためのファイルに書き出し、その URL を返す。同じスニペットのファイルは上書きし、前に書き出した別の名前のファイルは消すため、何度呼んでもファイルは 1 つになる。
///
/// ファイル名はスニペットの識別子のフォルダの中に置き、別のスニペットの同じ名前の添付と取り違えないようにする。
private func writeSnippetAttachmentFile(snippetID: UUID, attachmentData: Data, attachmentFileName: String) throws -> URL {
  let directoryURL = URL.cachesDirectory.appending(path: "SnippetAttachments", directoryHint: .isDirectory)
    .appending(path: snippetID.uuidString, directoryHint: .isDirectory)
  try? FileManager.default.removeItem(at: directoryURL)
  try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
  // ファイル名に区切りの `/` があるとフォルダの外を指すため、名前の最後の部分だけを使う。
  let fileURL = directoryURL.appending(path: (attachmentFileName as NSString).lastPathComponent, directoryHint: .notDirectory)
  try attachmentData.write(to: fileURL)
  return fileURL
}

/// アクセシビリティの許可があるか。⌘V のイベントを別のアプリへ送るのに要る。
func isAccessibilityTrusted() -> Bool {
  AXIsProcessTrusted()
}

/// 別のアプリへキー入力 (⌘V・バックスペース) を送る許可がすべてあるか。
///
/// `CGEvent.post` はアクセシビリティとは別にイベント送信 (PostEvent) の許可を求める場合がある。どちらもシステム設定の「アクセシビリティ」の一覧で与えるため、1 つにまとめて扱う。
func isSyntheticKeyStrokeAllowed() -> Bool {
  isAccessibilityTrusted() && CGPreflightPostEventAccess()
}

/// アクセシビリティとイベント送信の許可を求め、システム設定の「アクセシビリティ」を開く。
///
/// `AXIsProcessTrustedWithOptions` の問い合わせで、このアプリをアクセシビリティの一覧に載せる。載っていないとユーザーが「+」から自分でアプリを探して足す必要があるため。
/// 許可を求めるダイアログは初めて求めた時だけ出る。起動時に呼ぶと `make test` (アプリを起動して走る) の CI でダイアログが出たままになるため、ユーザーが案内のボタンを押した時だけ呼ぶ。
/// 冪等ではない: 許可が無い間は呼ぶたびにシステムの確認が出る。
func requestSyntheticKeyStrokeAccess() {
  // キーは `kAXTrustedCheckOptionPrompt` の値。この定数は C の書き換えられるグローバル変数として取り込まれ、Swift 6 の並行性の検査で参照できないため、同じ文字列を書く。
  _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
  CGRequestPostEventAccess()
  if let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
    NSWorkspace.shared.open(accessibilitySettingsURL)
  }
}

/// `application` を前面に戻し、⌘V を送ってクリップボードの中身を貼り付ける。許可が無いとイベントは届かないため、呼ぶ前に `isSyntheticKeyStrokeAllowed()` を確かめる。
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
