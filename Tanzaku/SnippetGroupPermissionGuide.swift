import SwiftUI

/// 許可を与えたかを確かめ直す間隔。システム設定で許可を切り替えてこの画面へ戻った時に、案内の表示がすぐ追いつくよう 1 秒にする。許可の確認はプロセス内の問い合わせだけで軽い。
private let snippetGroupPermissionRefreshInterval: Duration = .seconds(1)

/// スニペットグループのメニューに要る許可 (入力監視・アクセシビリティ) の案内。許可がすべてあれば何も出さない。
///
/// スニペットグループの編集画面の上に出す。許可はスニペットグループを作る時に初めて要るため、初回起動の手順では求めない (`documents/PROJECT.md`「設定・初回起動」)。
struct SnippetGroupPermissionGuide: View {
  /// 入力監視の許可があるか。
  @State private var isInputMonitoringGranted = isInputMonitoringAllowed()
  /// アクセシビリティ (イベント送信を含む) の許可があるか。
  @State private var isAccessibilityGranted = isSnippetGroupAccessibilityAllowed()

  var body: some View {
    Group {
      if !isInputMonitoringGranted || !isAccessibilityGranted {
        GroupBox {
          VStack(alignment: .leading, spacing: 10) {
            Text("Allow keyboard access to use snippet groups")
              .font(.headline)
            Text(
              "When you type a snippet group’s keyword, Tanzaku shows the menu at the text cursor and replaces the keyword with the snippet you choose. What you type is used only to find keywords, and is never saved or sent."
            )
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            permissionRow(title: "Input Monitoring", isGranted: isInputMonitoringGranted, action: requestInputMonitoringAccess)
              .accessibilityIdentifier("snippet-group-permission-input-monitoring")
            permissionRow(title: "Accessibility", isGranted: isAccessibilityGranted, action: requestSyntheticKeyStrokeAccess)
              .accessibilityIdentifier("snippet-group-permission-accessibility")
            Text("If the menu doesn’t appear after you allow access, quit and reopen Tanzaku.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .padding(6)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("snippet-group-permission-guide")
      }
    }
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: snippetGroupPermissionRefreshInterval)
        isInputMonitoringGranted = isInputMonitoringAllowed()
        isAccessibilityGranted = isSnippetGroupAccessibilityAllowed()
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
