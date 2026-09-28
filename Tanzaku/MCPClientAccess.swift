import Foundation
import SwiftData
import TanzakuKit

/// トークンで届いたリクエストの依頼元のクライアントを決める。受け付けられなければ `nil`。
///
/// 持ち主のいないトークン (設定に表示しているトークン) で届いた時は、そのトークンを新しいクライアントのものにする。
/// クライアント名は MCP のクライアントが名乗る `clientInfo` から取り、名乗らないリクエストは受け付けない (削除の確認画面と作成・更新の主体に出す名前が無いため)。
/// 次のクライアントのために、設定は新しい持ち主のいないトークンを表示する (`mcpUnboundToken(tokenStore:)`)。
func mcpRequestingClient(
  owner: MCPTokenOwner,
  tokens: [MCPTokenOwner: String],
  clientName: String?,
  modelContext: ModelContext,
  tokenStore: MCPTokenStore,
  now: Date
) throws -> MCPClient? {
  switch owner {
  case .client(let id):
    return try modelContext.fetch(FetchDescriptor<MCPClient>(predicate: #Predicate { $0.id == id })).first
  case .unbound:
    guard let clientName, let token = tokens[.unbound] else {
      return nil
    }
    let client = MCPClient(id: UUID(), name: clientName, createdAt: now)
    modelContext.insert(client)
    try modelContext.save()
    try tokenStore.saveToken(token, .client(id: client.id))
    try tokenStore.deleteToken(.unbound)
    return client
  }
}

/// MCP のクライアントが名乗った名前。`title` (表示名) を `name` より優先する。
///
/// 2026-07-28 以降の版はリクエストごとの `_meta` に、それより前の版は `initialize` の `clientInfo` に入る
/// ( https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning )。
func mcpClientName(method: String, params: [String: Any]) -> String? {
  let clientInfo =
    method == "initialize"
    ? params["clientInfo"] as? [String: Any]
    : (params["_meta"] as? [String: Any])?["io.modelcontextprotocol/clientInfo"] as? [String: Any]
  return [clientInfo?["title"], clientInfo?["name"]]
    .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
    .first { !$0.isEmpty }
}

/// クライアントの接続を取り消す。トークンとクライアントの記録を消し、以降そのトークンのリクエストは拒否される。
func revokeMCPClient(client: MCPClient, modelContext: ModelContext, tokenStore: MCPTokenStore) throws {
  try tokenStore.deleteToken(.client(id: client.id))
  modelContext.delete(client)
  try modelContext.save()
}
