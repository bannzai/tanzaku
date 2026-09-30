import Foundation
import LocalAuthentication

/// MCP のクライアントから依頼された削除を、ユーザーの認証で確定する。認証できた時だけ `true` を返し、キャンセル・失敗・認証できない Mac では `false` を返す。
///
/// `.deviceOwnerAuthentication` を使い、Touch ID が無い Mac・Touch ID が使えない時 (クラムシェルで外付けのキーボードに Touch ID が無い時など) はログインのパスワードで認証させる。
/// Touch ID だけ (`.deviceOwnerAuthenticationWithBiometrics`) にすると、その Mac では MCP から削除できなくなるため。
func authenticateSnippetDeletion(clientName: String) async -> Bool {
  let context = LAContext()
  let isAuthenticated = await withCheckedContinuation { continuation in
    context.evaluatePolicy(
      .deviceOwnerAuthentication,
      localizedReason: String(localized: "delete a snippet requested by \(clientName)")
    ) { @Sendable isAuthenticated, _ in
      continuation.resume(returning: isAuthenticated)
    }
  }
  // 認証の途中で LAContext が解放されると認証が取り消されるため、終わるまで参照を持ち、終わったら使えなくする。
  context.invalidate()
  return isAuthenticated
}
