import Foundation
import Security

/// MCP のアクセストークンの持ち主。
enum MCPTokenOwner: Hashable {
  /// 設定に表示している、まだどのクライアントも使っていないトークン。次に接続したクライアントのトークンになる。
  case unbound
  /// 接続を許可したクライアント (`MCPClient.id`) のトークン。
  case client(id: UUID)
}

/// MCP のアクセストークンの保管場所。アプリでは Keychain (`keychainMCPTokenStore()`)、テストではメモリに置く。
///
/// トークンはクライアントごとに 1 つ持つ。`MCPClient` のストアにはトークンを入れない (`documents/data-model.md`「MCPClient」)。
struct MCPTokenStore {
  /// 保管しているすべてのトークンを、持ち主ごとに読む。
  var loadTokens: () throws -> [MCPTokenOwner: String]
  /// 持ち主のトークンを保存する。すでにあれば置き換える。
  var saveToken: (_ token: String, _ owner: MCPTokenOwner) throws -> Void
  /// 持ち主のトークンを消す。無ければ何もしない。
  var deleteToken: (_ owner: MCPTokenOwner) throws -> Void
}

/// トークンの保管や読み出しに失敗した。`description` は画面にそのまま表示する。
struct MCPTokenStoreError: Error, CustomStringConvertible {
  /// Security framework の結果コード。
  var status: OSStatus

  /// 画面にそのまま表示する文言。
  var description: String {
    "Keychain error \(status): \(SecCopyErrorMessageString(status, nil) as String? ?? "unknown")"
  }
}

/// Keychain の項目のサービス名。アプリのバンドル ID に揃え、ほかのアプリの項目と区別する。
private let mcpTokenKeychainService = "com.bannzai.tanzaku.mcp-token"
/// 持ち主のいないトークンの Keychain の項目のアカウント名。クライアントのトークンは `MCPClient.id` の文字列にする。
private let mcpUnboundTokenKeychainAccount = "unbound"

/// Keychain の項目のアカウント名。
private func mcpTokenKeychainAccount(owner: MCPTokenOwner) -> String {
  switch owner {
  case .unbound:
    mcpUnboundTokenKeychainAccount
  case .client(let id):
    id.uuidString
  }
}

/// アカウント名から持ち主を読む。このアプリが書いた形でなければ `nil`。
private func mcpTokenOwner(keychainAccount: String) -> MCPTokenOwner? {
  if keychainAccount == mcpUnboundTokenKeychainAccount {
    return .unbound
  }
  return UUID(uuidString: keychainAccount).map { .client(id: $0) }
}

/// Keychain の汎用パスワードにトークンを置く保管場所。
///
/// `kSecUseDataProtectionKeychain` は使わない。データ保護の Keychain は Keychain のアクセスグループの entitlement を要り、署名しない CI・画面確認のビルド (`DebugUnsigned`) では使えないため。
func keychainMCPTokenStore() -> MCPTokenStore {
  MCPTokenStore(
    loadTokens: {
      var result: CFTypeRef?
      let status = SecItemCopyMatching(
        [
          kSecClass: kSecClassGenericPassword,
          kSecAttrService: mcpTokenKeychainService,
          kSecMatchLimit: kSecMatchLimitAll,
          kSecReturnAttributes: true,
          kSecReturnData: true,
        ] as CFDictionary,
        &result
      )
      if status == errSecItemNotFound {
        return [:]
      }
      guard status == errSecSuccess else {
        throw MCPTokenStoreError(status: status)
      }
      var tokens: [MCPTokenOwner: String] = [:]
      for item in result as? [[CFString: Any]] ?? [] {
        guard let owner = (item[kSecAttrAccount] as? String).flatMap({ mcpTokenOwner(keychainAccount: $0) }),
          let token = (item[kSecValueData] as? Data).flatMap({ String(data: $0, encoding: .utf8) })
        else {
          continue
        }
        tokens[owner] = token
      }
      return tokens
    },
    saveToken: { token, owner in
      let query: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: mcpTokenKeychainService,
        kSecAttrAccount: mcpTokenKeychainAccount(owner: owner),
      ]
      let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData: Data(token.utf8)] as CFDictionary)
      if updateStatus == errSecSuccess {
        return
      }
      guard updateStatus == errSecItemNotFound else {
        throw MCPTokenStoreError(status: updateStatus)
      }
      let addStatus = SecItemAdd(
        query.merging([kSecValueData: Data(token.utf8), kSecAttrLabel: "Tanzaku MCP access token"]) { current, _ in current } as CFDictionary,
        nil
      )
      guard addStatus == errSecSuccess else {
        throw MCPTokenStoreError(status: addStatus)
      }
    },
    deleteToken: { owner in
      let status = SecItemDelete(
        [
          kSecClass: kSecClassGenericPassword,
          kSecAttrService: mcpTokenKeychainService,
          kSecAttrAccount: mcpTokenKeychainAccount(owner: owner),
        ] as CFDictionary
      )
      guard status == errSecSuccess || status == errSecItemNotFound else {
        throw MCPTokenStoreError(status: status)
      }
    }
  )
}

/// メモリにトークンを置く保管場所。テストと、Keychain を使わないプレビューで使う。
func inMemoryMCPTokenStore(initialTokens: [MCPTokenOwner: String] = [:]) -> MCPTokenStore {
  // クロージャの間で同じ辞書を読み書きするため、参照型の箱に入れる。
  final class Box {
    var tokens: [MCPTokenOwner: String]
    init(tokens: [MCPTokenOwner: String]) {
      self.tokens = tokens
    }
  }
  let box = Box(tokens: initialTokens)
  return MCPTokenStore(
    loadTokens: { box.tokens },
    saveToken: { token, owner in
      box.tokens[owner] = token
    },
    deleteToken: { owner in
      box.tokens[owner] = nil
    }
  )
}

/// 新しいアクセストークンを作る。
///
/// 256 ビットの乱数を URL で使える Base64 にする。localhost の別のプロセスから総当たりで当てられない長さで、`claude mcp add --header` にそのまま書ける文字だけにするため。
func makeMCPAccessToken() -> String {
  var bytes = [UInt8](repeating: 0, count: 32)
  // SecRandomCopyBytes は乱数源が使えない時だけ失敗し、その時に弱いトークンを作らないよう止める。
  precondition(SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess, "SecRandomCopyBytes failed")
  return Data(bytes).base64EncodedString()
    .replacingOccurrences(of: "+", with: "-")
    .replacingOccurrences(of: "/", with: "_")
    .replacingOccurrences(of: "=", with: "")
}

/// 設定に表示する、持ち主のいないトークンを返す。無ければ作って保存する。
///
/// 何度呼んでも、再発行 (`reissueMCPUnboundToken(tokenStore:)`) かクライアントの接続までは同じトークンを返す。
func mcpUnboundToken(tokenStore: MCPTokenStore) throws -> String {
  if let token = try tokenStore.loadTokens()[.unbound] {
    return token
  }
  let token = makeMCPAccessToken()
  try tokenStore.saveToken(token, .unbound)
  return token
}

/// 持ち主のいないトークンを作り直す。前のトークンはどのクライアントも使っていないため、これで使えなくなるクライアントは無い。
/// 呼ぶたびに別のトークンになるため冪等ではない (再発行がこの操作の目的のため)。
func reissueMCPUnboundToken(tokenStore: MCPTokenStore) throws -> String {
  let token = makeMCPAccessToken()
  try tokenStore.saveToken(token, .unbound)
  return token
}

/// `Authorization` ヘッダーの Bearer トークンの持ち主を探す。一致するトークンが無ければ `nil`。
///
/// トークンの比較に掛かる時間から一致した文字数を推測されないよう、すべてのトークンを最後まで比べる。
func mcpTokenOwner(authorizationHeader: String?, tokens: [MCPTokenOwner: String]) -> MCPTokenOwner? {
  guard let authorizationHeader, authorizationHeader.lowercased().hasPrefix("bearer ") else {
    return nil
  }
  let presentedToken = Array(authorizationHeader.dropFirst("bearer ".count).trimmingCharacters(in: .whitespaces).utf8)
  var matchedOwner: MCPTokenOwner?
  for (owner, token) in tokens where constantTimeEquals(lhs: presentedToken, rhs: Array(token.utf8)) {
    matchedOwner = owner
  }
  return matchedOwner
}

/// 長さが同じなら、どこで違っても同じ時間で比べる。
func constantTimeEquals(lhs: [UInt8], rhs: [UInt8]) -> Bool {
  guard lhs.count == rhs.count else {
    return false
  }
  return zip(lhs, rhs).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
}
