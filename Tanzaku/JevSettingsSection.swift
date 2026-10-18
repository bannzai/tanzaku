import SwiftUI
import TanzakuKit

/// 設定の「一般」の Jev (TypeSafe の判定 API) の API キーの欄 (issue #64)。キーを保存した時だけ、ランチャーの意味検索で Jev を使う。
///
/// キーは Keychain にだけ置き (`saveJevAPIKey(apiKey:)`)、保存した後は画面に出さず「保存済み」と削除のボタンだけを出す。入力の欄は `SecureField` で伏せる。
struct JevSettingsSection: View {
  /// Keychain にキーがあるか。キーの値は画面の状態に持たない。
  @State private var isJevAPIKeySaved = false
  /// 保存する前の入力。保存したら空にする。
  @State private var jevAPIKeyInput = ""
  /// Keychain の読み書きの失敗。Keychain の結果コードだけでキーを含まない (`MCPTokenStoreError`)。
  @State private var jevAPIKeyErrorMessage: String?

  var body: some View {
    Section {
      if isJevAPIKeySaved {
        LabeledContent {
          Button("Remove API Key") {
            updateJevAPIKey {
              try deleteJevAPIKey()
            }
          }
          .accessibilityIdentifier("jev-api-key-remove-button")
        } label: {
          Text("TypeSafe API key")
          Text("Saved in the Keychain on this Mac")
        }
      } else {
        LabeledContent {
          HStack(spacing: 8) {
            // Form の中では題が欄の外の見出しになり欄が空に見えるため、題を空にして欄の中の薄い文字 (prompt) で示す。
            SecureField("", text: $jevAPIKeyInput, prompt: Text("API key"))
              .textFieldStyle(.roundedBorder)
              .frame(width: 220)
              .accessibilityIdentifier("jev-api-key-field")
            Button("Save") {
              let apiKey = jevAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
              updateJevAPIKey {
                try saveJevAPIKey(apiKey: apiKey)
              }
            }
            .disabled(jevAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("jev-api-key-save-button")
          }
        } label: {
          Text("TypeSafe API key")
          Text("Ranks semantic search results with Jev")
        }
      }
      if let jevAPIKeyErrorMessage {
        Text(verbatim: jevAPIKeyErrorMessage)
          .foregroundStyle(.red)
      }
      Text(
        "When you save a key, the launcher sends your search text and the beginning of up to \(jevRerankCandidateCount) snippets closest in meaning to the TypeSafe API (Jev) to rank the semantic search results. Text that looks like a token or password is masked before sending. Without a key, search stays on this Mac."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .accessibilityIdentifier("jev-api-key-note")
    } header: {
      Text("Semantic Search with Jev")
    }
    .onAppear {
      updateJevAPIKey {}
    }
  }

  /// Keychain の操作を行い、キーがあるかを読み直す。失敗したら理由を出す。保存の後は入力を空にする。
  private func updateJevAPIKey(operation: () throws -> Void) {
    do {
      try operation()
      // 保存の後に読み直しが失敗しても、保存したキーが入力の欄に残らないよう、読み直しの前に空にする。
      jevAPIKeyInput = ""
      isJevAPIKeySaved = try loadJevAPIKey() != nil
      jevAPIKeyErrorMessage = nil
    } catch {
      jevAPIKeyErrorMessage = String(describing: error)
    }
  }
}
