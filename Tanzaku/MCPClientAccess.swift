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
    // 途中で失敗しても同じトークンが 2 つの持ち主に残らないよう、持ち主のいないトークンを先に消してから、クライアントのトークンとして保存する。
    // 途中で失敗するとトークンはどちらにも残らず、そのリクエストは拒否される (接続し直すには設定の新しいトークンを使う)。
    // 両方に残ると、クライアントの接続を取り消しても持ち主のいないトークンとして使い続けられるため、この順にする。
    let clientID = UUID()
    try tokenStore.deleteToken(.unbound)
    try tokenStore.saveToken(token, .client(id: clientID))
    let client = MCPClient(id: clientID, name: clientName, createdAt: now)
    modelContext.insert(client)
    do {
      try modelContext.save()
    } catch {
      try? tokenStore.deleteToken(.client(id: clientID))
      throw error
    }
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
