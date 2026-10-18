import Foundation
import Security

/// Jev (TypeSafe の判定 API) の API キーの Keychain の項目のサービス名。アプリのバンドル ID に揃え、ほかのアプリの項目と区別する。
private let jevAPIKeyKeychainService = "com.bannzai.tanzaku.jev-api-key"
/// Jev の API キーの Keychain の項目のアカウント名。キーは Mac に 1 つだけ持つ。
private let jevAPIKeyKeychainAccount = "typesafe"

/// Jev の API キーの Keychain の項目を探す条件。
///
/// `kSecAttrSynchronizable` を指定しないため iCloud キーチェーンへ同期しない (キーはその Mac に入れたものだけにする。issue #64)。
/// `kSecUseDataProtectionKeychain` は使わない。署名しない CI・画面確認のビルド (`DebugUnsigned`) で使えないため (`keychainMCPTokenStore()` と同じ)。
private let jevAPIKeyKeychainQuery: [CFString: Any] = [
  kSecClass: kSecClassGenericPassword,
  kSecAttrService: jevAPIKeyKeychainService,
  kSecAttrAccount: jevAPIKeyKeychainAccount,
]

/// Keychain から Jev の API キーを読む。保存していなければ `nil`。失敗した時は `MCPTokenStoreError` (Keychain の結果コード) を投げる。
func loadJevAPIKey() throws -> String? {
  var dataResult: CFTypeRef?
  let status = SecItemCopyMatching(
    jevAPIKeyKeychainQuery.merging([kSecMatchLimit: kSecMatchLimitOne, kSecReturnData: true]) { current, _ in current } as CFDictionary,
    &dataResult
  )
  if status == errSecItemNotFound {
    return nil
  }
  guard status == errSecSuccess else {
    throw MCPTokenStoreError(status: status)
  }
  return (dataResult as? Data).flatMap { String(data: $0, encoding: .utf8) }
}

/// Jev の API キーを Keychain に保存する。すでにあれば置き換える。
func saveJevAPIKey(apiKey: String) throws {
  let updateStatus = SecItemUpdate(jevAPIKeyKeychainQuery as CFDictionary, [kSecValueData: Data(apiKey.utf8)] as CFDictionary)
  if updateStatus == errSecSuccess {
    return
  }
  guard updateStatus == errSecItemNotFound else {
    throw MCPTokenStoreError(status: updateStatus)
  }
  let addStatus = SecItemAdd(
    jevAPIKeyKeychainQuery.merging([kSecValueData: Data(apiKey.utf8), kSecAttrLabel: "Tanzaku TypeSafe API key"]) { current, _ in current }
      as CFDictionary,
    nil
  )
  guard addStatus == errSecSuccess else {
    throw MCPTokenStoreError(status: addStatus)
  }
}

/// Jev の API キーを Keychain から消す。無ければ何もしない。
func deleteJevAPIKey() throws {
  let status = SecItemDelete(jevAPIKeyKeychainQuery as CFDictionary)
  guard status == errSecSuccess || status == errSecItemNotFound else {
    throw MCPTokenStoreError(status: status)
  }
}
