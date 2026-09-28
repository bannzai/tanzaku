import Foundation
import SwiftData
import TanzakuKit

/// MCP のサーバーとして名乗る名前。Claude Code に登録するサーバー名 (`claude mcp add ... tanzaku`) にもそろえる。
let mcpServerName = "tanzaku"

/// Streamable HTTP の MCP のエンドポイントのパス。
let mcpEndpointPath = "/mcp"

/// リクエストごとに `_meta` で版を送る版 (modern)。
let mcpModernProtocolVersions = ["2026-07-28"]

/// `initialize` で版を決める版 (legacy)。新しい順。Streamable HTTP を使える版 (2025-03-26 以降) だけを受け付ける。
let mcpLegacyProtocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26"]

/// MCP のリクエストを処理するのに要る、アプリの状態と副作用。アプリでは Keychain・埋め込みモデル・Touch ID の確認を、テストではその代わりを渡す。
struct MCPServerEnvironment {
  /// スニペットと `MCPClient` を読み書きするコンテキスト。
  var modelContext: ModelContext
  /// アクセストークンの保管場所。
  var tokenStore: MCPTokenStore
  /// 待ち受けるポート。`Origin` の検査に使う。
  var port: Int
  /// 意味検索の埋め込みモデル。資産のダウンロードが済むまでは `nil`。
  var embedder: @MainActor () -> SnippetTextEmbedder?
  /// 削除の前に確認を求めるか (設定の「削除に Touch ID を求める」)。
  var requiresDeletionConfirmation: @MainActor () -> Bool
  /// 削除の確認を出し、ユーザーが認証して許可した時だけ `true` を返す。
  var confirmSnippetDeletion: @MainActor (SnippetDeletionRequest) async -> Bool
  /// 今の日時。
  var now: @MainActor () -> Date
}

/// MCP のエンドポイントに届いた HTTP リクエストを処理して、返すレスポンスを作る。
///
/// Streamable HTTP の 2026-07-28 の版 (リクエストごとの `_meta`) と、それより前の版 (`initialize`) の両方のクライアントを受け付ける
/// ( https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning#backward-compatibility-with-initialization-based-versions )。
/// セッション (`Mcp-Session-Id`) は発行せず、1 つのリクエストに 1 つの JSON で答える。サーバーから送る通知が無いため、SSE のストリームも開かない。
func handleMCPHTTPRequest(request: MCPHTTPRequest, environment: MCPServerEnvironment) async -> MCPHTTPResponse {
  guard request.path == mcpEndpointPath else {
    return MCPHTTPResponse(statusCode: 404, headers: [:], body: Data())
  }
  guard request.method == "POST" else {
    return MCPHTTPResponse(statusCode: 405, headers: ["Allow": "POST"], body: Data())
  }
  // DNS rebinding で Web ページからこの Mac のサーバーを呼ばせないため、ブラウザが付ける Origin はこのサーバー自身のものだけを受け付ける。
  if let origin = request.headers["origin"], !["http://127.0.0.1:\(environment.port)", "http://localhost:\(environment.port)"].contains(origin) {
    return mcpJSONRPCErrorResponse(statusCode: 403, id: nil, code: -32600, message: "Forbidden origin")
  }
  let tokens: [MCPTokenOwner: String]
  do {
    tokens = try environment.tokenStore.loadTokens()
  } catch {
    return mcpJSONRPCErrorResponse(statusCode: 500, id: nil, code: -32603, message: "\(error)")
  }
  guard let owner = mcpTokenOwner(authorizationHeader: request.headers["authorization"], tokens: tokens) else {
    return mcpUnauthorizedResponse(message: "Missing or revoked access token. Copy the command in Tanzaku Settings > AI Agents.")
  }
  guard let message = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] else {
    return mcpJSONRPCErrorResponse(statusCode: 400, id: nil, code: -32700, message: "Parse error")
  }
  let id = message["id"]
  guard message["jsonrpc"] as? String == "2.0", let method = message["method"] as? String else {
    return mcpJSONRPCErrorResponse(statusCode: 400, id: id, code: -32600, message: "Invalid Request")
  }
  let params = message["params"] as? [String: Any] ?? [:]
  let modernProtocolVersion = (params["_meta"] as? [String: Any])?["io.modelcontextprotocol/protocolVersion"] as? String
  if let protocolVersionErrorResponse = mcpProtocolVersionErrorResponse(
    request: request,
    id: id,
    method: method,
    params: params,
    modernProtocolVersion: modernProtocolVersion
  ) {
    return protocolVersionErrorResponse
  }

  let client: MCPClient
  do {
    guard
      let requestingClient = try mcpRequestingClient(
        owner: owner,
        tokens: tokens,
        clientName: mcpClientName(method: method, params: params),
        modelContext: environment.modelContext,
        tokenStore: environment.tokenStore,
        now: environment.now()
      )
    else {
      return mcpUnauthorizedResponse(message: "This access token is not bound to a client yet. Send a request with clientInfo first.")
    }
    client = requestingClient
    client.lastUsedAt = environment.now()
    try environment.modelContext.save()
  } catch {
    return mcpJSONRPCErrorResponse(statusCode: 500, id: id, code: -32603, message: "\(error)")
  }

  guard let id else {
    // クライアントからの通知 (`notifications/initialized` など) に応じてすることは無い。
    return MCPHTTPResponse(statusCode: 202, headers: [:], body: Data())
  }
  do {
    return mcpJSONRPCResultResponse(
      id: id,
      result: try await mcpResult(method: method, params: params, client: client, environment: environment)
    )
  } catch let error as MCPProtocolError {
    // 2026-07-28 の版は、知らないメソッドを 404 で返す決まり (Streamable HTTP「Protocol Version Header」)。
    let statusCode = error.code == -32601 && modernProtocolVersion != nil ? 404 : 200
    return mcpJSONRPCErrorResponse(statusCode: statusCode, id: id, code: error.code, message: error.message)
  } catch {
    return mcpJSONRPCErrorResponse(statusCode: 200, id: id, code: -32603, message: "\(error)")
  }
}

/// 版とヘッダーの検査に通らなければ、そのエラーのレスポンスを返す。
///
/// 2026-07-28 の版は、ボディの版・メソッド・ツール名を写したヘッダーがボディと一致することを求める (Streamable HTTP「Server Validation」)。
/// それより前の版のクライアントは `MCP-Protocol-Version` を付けないことがあり (2025-06-18 より前の版)、付けていれば受け付ける版かだけを見る。
func mcpProtocolVersionErrorResponse(
  request: MCPHTTPRequest,
  id: Any?,
  method: String,
  params: [String: Any],
  modernProtocolVersion: String?
) -> MCPHTTPResponse? {
  let supportedVersions = mcpModernProtocolVersions + mcpLegacyProtocolVersions
  guard let modernProtocolVersion else {
    if let headerVersion = request.headers["mcp-protocol-version"], !mcpLegacyProtocolVersions.contains(headerVersion) {
      return mcpJSONRPCErrorResponse(
        statusCode: 400,
        id: id,
        code: -32022,
        message: "Unsupported protocol version",
        data: ["supported": supportedVersions, "requested": headerVersion] as [String: Any]
      )
    }
    return nil
  }
  guard mcpModernProtocolVersions.contains(modernProtocolVersion) else {
    return mcpJSONRPCErrorResponse(
      statusCode: 400,
      id: id,
      code: -32022,
      message: "Unsupported protocol version",
      data: ["supported": supportedVersions, "requested": modernProtocolVersion] as [String: Any]
    )
  }
  guard request.headers["mcp-protocol-version"] == modernProtocolVersion else {
    return mcpJSONRPCErrorResponse(statusCode: 400, id: id, code: -32020, message: "Header mismatch: MCP-Protocol-Version")
  }
  guard request.headers["mcp-method"] == method else {
    return mcpJSONRPCErrorResponse(statusCode: 400, id: id, code: -32020, message: "Header mismatch: Mcp-Method")
  }
  if method == "tools/call", request.headers["mcp-name"].map({ decodedMCPHeaderValue(headerValue: $0) }) != params["name"] as? String {
    return mcpJSONRPCErrorResponse(statusCode: 400, id: id, code: -32020, message: "Header mismatch: Mcp-Name")
  }
  return nil
}

/// `Mcp-Name` などのヘッダーの値を読む。ASCII で書けない値は `=?base64?...?=` で届く (Streamable HTTP「Value Encoding」)。
func decodedMCPHeaderValue(headerValue: String) -> String? {
  guard headerValue.hasPrefix("=?base64?"), headerValue.hasSuffix("?=") else {
    return headerValue
  }
  return Data(base64Encoded: String(headerValue.dropFirst("=?base64?".count).dropLast("?=".count)))
    .flatMap { String(data: $0, encoding: .utf8) }
}

/// JSON-RPC のメソッドを実行し、`result` を返す。
func mcpResult(method: String, params: [String: Any], client: MCPClient, environment: MCPServerEnvironment) async throws -> [String: Any] {
  let serverInfo: [String: Any] = ["name": mcpServerName, "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"]
  switch method {
  case "initialize":
    let requestedVersion = params["protocolVersion"] as? String
    return [
      // クライアントが求めた版を受け付けられなければ、受け付ける最も新しい版を返し、クライアントに選ばせる (2025-11-25「Version Negotiation」)。
      "protocolVersion": requestedVersion.flatMap { mcpLegacyProtocolVersions.contains($0) ? $0 : nil } ?? mcpLegacyProtocolVersions[0],
      "capabilities": ["tools": [String: Any]()],
      "serverInfo": serverInfo,
      "instructions": mcpServerInstructions,
    ]
  case "server/discover":
    return [
      "resultType": "complete",
      "supportedVersions": mcpModernProtocolVersions + mcpLegacyProtocolVersions,
      "capabilities": ["tools": [String: Any]()],
      "_meta": ["io.modelcontextprotocol/serverInfo": serverInfo],
      "instructions": mcpServerInstructions,
    ]
  case "ping":
    return ["resultType": "complete"]
  case "tools/list":
    return ["resultType": "complete", "tools": mcpToolDefinitions]
  case "tools/call":
    guard let name = params["name"] as? String else {
      throw MCPProtocolError(code: -32602, message: "Missing tool name")
    }
    return try await callMCPTool(name: name, arguments: params["arguments"] as? [String: Any] ?? [:], client: client, environment: environment)
  default:
    throw MCPProtocolError(code: -32601, message: "Method not found: \(method)")
  }
}

/// エージェントに渡すサーバーの使い方。
let mcpServerInstructions =
  "Tanzaku stores the user's snippets (reusable text, commands, and prompts). Search before creating to avoid duplicates. Deleting asks the user to confirm with Touch ID, so explain the reason clearly."

/// JSON-RPC の結果のレスポンス。
func mcpJSONRPCResultResponse(id: Any, result: [String: Any]) -> MCPHTTPResponse {
  MCPHTTPResponse(statusCode: 200, headers: [:], body: mcpJSONData(object: ["jsonrpc": "2.0", "id": id, "result": result] as [String: Any]))
}

/// JSON-RPC のエラーのレスポンス。リクエストの `id` が読めない時は `null` にする (JSON-RPC 2.0「Response object」)。
func mcpJSONRPCErrorResponse(statusCode: Int, id: Any?, code: Int, message: String, data: Any? = nil) -> MCPHTTPResponse {
  var error: [String: Any] = ["code": code, "message": message]
  error["data"] = data
  return MCPHTTPResponse(statusCode: statusCode, headers: [:], body: mcpJSONData(object: ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": error] as [String: Any]))
}

/// トークンが無い・取り消されたリクエストのレスポンス。
func mcpUnauthorizedResponse(message: String) -> MCPHTTPResponse {
  // -32000〜-32099 は MCP と SDK が意味を割り当てて使うため (例: -32020 HeaderMismatch)、JSON-RPC の Invalid Request を使う。
  var response = mcpJSONRPCErrorResponse(statusCode: 401, id: nil, code: -32600, message: message)
  // 401 には認証の方式を示すヘッダーが要る (RFC 9110 11.6.1)。
  response.headers["WWW-Authenticate"] = #"Bearer realm="tanzaku""#
  return response
}

/// JSON の値をレスポンスの本文にする。キーの順を固定し、同じ結果が同じバイト列になるようにする。
func mcpJSONData(object: Any) -> Data {
  (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
}
