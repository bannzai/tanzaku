import SwiftUI

/// 許可を与えたかを確かめ直す間隔。システム設定で許可を切り替えてこの画面へ戻った時に、案内の表示がすぐ追いつくよう 1 秒にする。許可の確認はプロセス内の問い合わせだけで軽い。
private let snippetGroupPermissionRefreshInterval: Duration = .seconds(1)

/// キーワード展開 (スニペットのキーワードの置き換えとスニペットグループのメニュー) に要る許可 (入力監視・アクセシビリティ) の案内。
///
/// 起動時と開き直した時に出す許可のウィンドウの中身 (`AppDelegate.showKeywordPermissionWindowIfNeeded()`)。編集画面には出さない (`documents/DIRECTION.md`「決めたこと」の 2026-10-17 の行)。
/// 許可は実行中に与えても、起動し直すまでイベント送信の許可 (`CGPreflightPostEventAccess`) の値が変わらないため、開き直すボタンを置く ( https://developer.apple.com/forums/thread/727984 )。
struct SnippetGroupPermissionGuide: View {
  /// 許可がすべてそろった時に呼ぶ。ウィンドウはここでキー入力の監視を始めて閉じる。
  let onAllowed: () -> Void
  /// 入力監視の許可があるか。
  @State private var isInputMonitoringGranted = isInputMonitoringAllowed()
  /// アクセシビリティ (イベント送信を含む) の許可があるか。
  @State private var isAccessibilityGranted = isSnippetGroupAccessibilityAllowed()
  /// アクセシビリティの一覧でオンにしたが、イベント送信の許可が起動時の値のままで、開き直さないと効かない状態か。
  @State private var isRelaunchNeeded = isKeywordPermissionRelaunchNeeded()

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Allow keyboard access to expand keywords")
        .font(.headline)
      Text(
        "When you type a snippet’s keyword, Tanzaku replaces it with the snippet. When you type a snippet group’s keyword, Tanzaku shows the menu at the text cursor and replaces the keyword with the snippet you choose. What you type is used only to find keywords, and is never saved or sent."
      )
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      permissionRow(title: "Input Monitoring", isGranted: isInputMonitoringGranted, action: requestInputMonitoringAccess)
        .accessibilityIdentifier("snippet-group-permission-input-monitoring")
      permissionRow(title: "Accessibility", isGranted: isAccessibilityGranted, action: requestSyntheticKeyStrokeAccess)
        .accessibilityIdentifier("snippet-group-permission-accessibility")
      HStack(alignment: .firstTextBaseline) {
        Text("Tanzaku can’t see permission changes while it’s running. After you allow access, reopen Tanzaku.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Spacer()
        if isRelaunchNeeded {
          Button("Reopen Tanzaku", action: relaunchApplication)
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("snippet-group-permission-reopen")
        } else {
          Button("Reopen Tanzaku", action: relaunchApplication)
            .accessibilityIdentifier("snippet-group-permission-reopen")
        }
      }
    }
    .padding(20)
    .frame(width: 520, alignment: .leading)
    // 子の要素の identifier (開き直すボタン等) を、まとまりの identifier で上書きしないため。
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("snippet-group-permission-guide")
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: snippetGroupPermissionRefreshInterval)
        isInputMonitoringGranted = isInputMonitoringAllowed()
        isAccessibilityGranted = isSnippetGroupAccessibilityAllowed()
        isRelaunchNeeded = isKeywordPermissionRelaunchNeeded()
        if isInputMonitoringGranted, isAccessibilityGranted {
          onAllowed()
          return
        }
      }
    }
  }

  /// 許可 1 つの行。許可があれば「許可済み」、無ければシステム設定を開くボタンを出す。
  private func permissionRow(title: LocalizedStringKey, isGranted: Bool, action: @escaping () -> Void) -> some View {
    HStack {
      Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle")
        .foregroundStyle(isGranted ? .green : .orange)
      Text(title)
      Spacer()
      if isGranted {
        Text("Allowed")
          .foregroundStyle(.secondary)
      } else {
        Button("Open System Settings", action: action)
      }
    }
  }
}
