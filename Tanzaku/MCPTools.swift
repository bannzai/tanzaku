import Foundation
import SwiftData
import TanzakuKit

/// `Snippet.createdByKind` / `updatedByKind` の、MCP のクライアントが作成・更新したことを表す値 (`documents/data-model.md`「Snippet」)。
let snippetAuthorKindMCP = "mcp"

/// MCP の削除のツールが、確認の画面に出す依頼。
struct SnippetDeletionRequest: Identifiable {
  /// 確認の画面を依頼ごとに区別する識別子。
  var id = UUID()
  /// 依頼元のクライアント名。
  var clientName: String
  /// エージェントが書いた削除の理由。
  var reason: String
  /// 削除するスニペット。
  var snippet: Snippet
  /// 依頼を受けた日時。
  var receivedAt: Date
}

/// MCP のツールの実行の失敗。エージェントが直して呼び直せるよう、JSON-RPC のエラーではなくツールの結果 (`isError: true`) として返す
/// ( https://modelcontextprotocol.io/specification/2026-07-28/server/tools#error-handling )。
struct MCPToolError: Error, CustomStringConvertible {
  /// エージェントに返す文言。スニペットの本文を入れない (`.claude/rules/snippet-content-handling.md`)。
  var description: String
}

/// JSON-RPC のエラーとして返す失敗。リクエストの形そのものが誤っている時に使う。
struct MCPProtocolError: Error {
  /// JSON-RPC のエラーコード。
  var code: Int
  /// エラーの文言。
  var message: String
}

/// 検索のツールが返す文字列の一致の件数の既定値。エージェントのコンテキストに本文を入れすぎないため、ランチャーの 1 画面に並ぶ程度にとどめる。
let mcpSearchDefaultLimit = 20

/// `tools/list` で返すツールの定義。並びは返す順で、クライアントがキャッシュできるよう毎回同じにする。
let mcpToolDefinitions: [[String: Any]] = [
  [
    "name": "search_snippets",
    "title": "Search snippets",
    "description":
      "Searches the user's Tanzaku snippets. Returns snippets whose keyword, title, or body matches the query (keywordMatches), and snippets found by on-device semantic search (semanticMatches).",
    "inputSchema": [
      "type": "object",
      "properties": [
        "query": ["type": "string", "description": "Words to search for. Japanese and English are supported."],
        "limit": ["type": "integer", "description": "Maximum number of keywordMatches to return. Defaults to \(mcpSearchDefaultLimit).", "minimum": 1] as [String: Any],
      ] as [String: Any],
      "required": ["query"],
    ] as [String: Any],
    "annotations": ["readOnlyHint": true],
  ],
  [
    "name": "get_snippet",
    "title": "Get a snippet",
    "description": "Gets one snippet by its id.",
    "inputSchema": [
      "type": "object",
      "properties": ["id": ["type": "string", "description": "The snippet id (UUID)."]],
      "required": ["id"],
    ] as [String: Any],
    "annotations": ["readOnlyHint": true],
  ],
  [
    "name": "create_snippet",
    "title": "Create a snippet",
    "description":
      "Creates a snippet. Only body is required. The keyword must be unique among snippets and snippet groups. The snippet is recorded as created by this MCP client.",
    "inputSchema": [
      "type": "object",
      "properties": [
        "body": ["type": "string", "description": "The text to output. Must not be empty."],
        "title": ["type": "string", "description": "Display name. Without it, the first line of the body is shown."],
        "keyword": ["type": "string", "description": "Abbreviation that expands to the body."],
        "language": ["type": "string", "description": "Language for syntax highlighting, such as swift or shell. Omit for plain text."],
      ],
      "required": ["body"],
    ] as [String: Any],
    "annotations": ["readOnlyHint": false, "destructiveHint": false],
  ],
  [
    "name": "update_snippet",
    "title": "Update a snippet",
    "description":
      "Updates a snippet. Only the given fields change. Pass an empty string to clear title, keyword, or language. The snippet is recorded as updated by this MCP client.",
    "inputSchema": [
      "type": "object",
      "properties": [
        "id": ["type": "string", "description": "The snippet id (UUID)."],
        "body": ["type": "string", "description": "The text to output. Must not be empty."],
        "title": ["type": "string"],
        "keyword": ["type": "string"],
        "language": ["type": "string"],
      ],
      "required": ["id"],
    ] as [String: Any],
    "annotations": ["readOnlyHint": false, "destructiveHint": true, "idempotentHint": true],
  ],
  [
    "name": "delete_snippet",
    "title": "Delete a snippet",
    "description":
      "Deletes a snippet. Tanzaku shows the user your client name, the reason, and the full snippet, and deletes it only after the user confirms with Touch ID. Write the reason so that the user can decide.",
    "inputSchema": [
      "type": "object",
      "properties": [
        "id": ["type": "string", "description": "The snippet id (UUID)."],
        "reason": ["type": "string", "description": "Why the snippet should be deleted. Shown to the user."],
      ],
      "required": ["id", "reason"],
    ] as [String: Any],
    "annotations": ["readOnlyHint": false, "destructiveHint": true],
  ],
]

/// ツールを実行し、`tools/call` の結果を返す。
///
/// 知らないツール名は JSON-RPC のエラー (`MCPProtocolError`) にし、引数の誤り・見つからないスニペット・保存前の検査の失敗はツールの結果 (`isError: true`) にする。
/// 失敗したツールの変更は取り消す。残すと同じコンテキストの次の保存 (最後のアクセスの記録など) で、失敗した操作まで保存されるため。
func callMCPTool(name: String, arguments: [String: Any], client: MCPClient, environment: MCPServerEnvironment) async throws -> [String: Any] {
  do {
    return try await mcpToolResult(name: name, arguments: arguments, client: client, environment: environment)
  } catch {
    environment.modelContext.rollback()
    throw error
  }
}

/// ツールを実行した `tools/call` の結果。ツールのエラーにする失敗は結果にし、それ以外は投げる。
private func mcpToolResult(name: String, arguments: [String: Any], client: MCPClient, environment: MCPServerEnvironment) async throws -> [String: Any] {
  do {
    let structuredContent: [String: Any]
    switch name {
    case "search_snippets":
      structuredContent = try searchSnippetsTool(arguments: arguments, environment: environment)
    case "get_snippet":
      structuredContent = ["snippet": mcpSnippetJSONObject(snippet: try fetchSnippetArgument(arguments: arguments, modelContext: environment.modelContext))]
    case "create_snippet":
      structuredContent = ["snippet": mcpSnippetJSONObject(snippet: try createSnippetTool(arguments: arguments, client: client, environment: environment))]
    case "update_snippet":
      structuredContent = ["snippet": mcpSnippetJSONObject(snippet: try updateSnippetTool(arguments: arguments, client: client, environment: environment))]
    case "delete_snippet":
      structuredContent = try await deleteSnippetTool(arguments: arguments, client: client, environment: environment)
    default:
      throw MCPProtocolError(code: -32602, message: "Unknown tool: \(name)")
    }
    return [
      "resultType": "complete",
      "content": [["type": "text", "text": mcpJSONText(object: structuredContent)]],
      "structuredContent": structuredContent,
      "isError": false,
    ]
  } catch let error as MCPToolError {
    environment.modelContext.rollback()
    return mcpToolErrorResult(message: error.description)
  } catch let error as SnippetValidationError {
    environment.modelContext.rollback()
    return mcpToolErrorResult(message: error.description)
  }
}

/// ツールの実行の失敗を表す `tools/call` の結果。
func mcpToolErrorResult(message: String) -> [String: Any] {
  ["resultType": "complete", "content": [["type": "text", "text": message]], "isError": true]
}

/// ツールが返すスニペット。属性の意味は `documents/data-model.md`「Snippet」。ツールの応答はエージェントが使うため本文を含める。
func mcpSnippetJSONObject(snippet: Snippet) -> [String: Any] {
  [
    "id": snippet.id.uuidString,
    "body": snippet.body,
    "title": mcpJSONNullable(text: snippet.title),
    "keyword": mcpJSONNullable(text: snippet.keyword),
    "language": mcpJSONNullable(text: snippet.language),
    "color": mcpJSONNullable(text: snippet.colorRawValue),
    "folder": mcpJSONNullable(text: snippet.folder?.name),
    "tags": (snippet.tags ?? []).map(\.name).sorted(),
    "createdAt": snippet.createdAt.ISO8601Format(),
    "updatedAt": snippet.updatedAt.ISO8601Format(),
    "createdByKind": snippet.createdByKind,
    "createdByClientName": mcpJSONNullable(text: snippet.createdByClientName),
    "updatedByKind": snippet.updatedByKind,
    "updatedByClientName": mcpJSONNullable(text: snippet.updatedByClientName),
  ]
}

/// 値が無ければ JSON の `null` にする。キーを省かずに `null` を返し、エージェントが属性の有無を読み違えないようにする。
func mcpJSONNullable(text: String?) -> Any {
  text.map { $0 as Any } ?? NSNull()
}

/// JSON の値をテキストの内容にする。`structuredContent` を読まない古いクライアントのため、同じ内容をテキストでも返す
/// ( https://modelcontextprotocol.io/specification/2026-07-28/server/tools#structured-content )。
func mcpJSONText(object: Any) -> String {
  String(decoding: mcpJSONData(object: object), as: UTF8.self)
}

/// 引数の文字列を読む。無ければ `nil`、`null` は空文字として扱う (更新のツールで値を消す指定になる)。
func mcpStringArgument(arguments: [String: Any], name: String) throws -> String? {
  switch arguments[name] {
  case nil:
    return nil
  case is NSNull:
    return ""
  case let value as String:
    return value
  default:
    throw MCPToolError(description: "The argument \"\(name)\" must be a string.")
  }
}

/// 必ず要る引数の文字列を読む。無いか空白だけなら失敗にする。
func mcpRequiredStringArgument(arguments: [String: Any], name: String) throws -> String {
  guard let value = try mcpStringArgument(arguments: arguments, name: name), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
    throw MCPToolError(description: "The argument \"\(name)\" is required.")
  }
  return value
}

/// 引数 `id` のスニペットを読む。
func fetchSnippetArgument(arguments: [String: Any], modelContext: ModelContext) throws -> Snippet {
  let idText = try mcpRequiredStringArgument(arguments: arguments, name: "id")
  guard let id = UUID(uuidString: idText) else {
    throw MCPToolError(description: "The id \"\(idText)\" is not a UUID.")
  }
  guard let snippet = try modelContext.fetch(FetchDescriptor<Snippet>(predicate: #Predicate { $0.id == id })).first else {
    throw MCPToolError(description: "No snippet has the id \(idText).")
  }
  return snippet
}

/// 空文字をキーワード・タイトル・言語なしとして保存する。キーワードの空文字はキーワードなしとして扱う決まり (`documents/DIRECTION.md`「決めたこと」) に、タイトルと言語もそろえる。
func mcpOptionalText(text: String) -> String? {
  text.isEmpty ? nil : text
}

/// `search_snippets` の結果。
func searchSnippetsTool(arguments: [String: Any], environment: MCPServerEnvironment) throws -> [String: Any] {
  let query = try mcpRequiredStringArgument(arguments: arguments, name: "query")
  let limit: Int
  switch arguments["limit"] {
  case nil:
    limit = mcpSearchDefaultLimit
  case let value as Int where value >= 1:
    limit = value
  default:
    throw MCPToolError(description: "The argument \"limit\" must be a positive integer.")
  }
  let result = try searchSnippets(query: query, modelContext: environment.modelContext, embedder: environment.embedder())
  return [
    "keywordMatches": result.keywordMatches.prefix(limit).map { match in
      ["match": mcpKeywordMatchKindText(kind: match.kind), "snippet": mcpSnippetJSONObject(snippet: match.snippet)] as [String: Any]
    },
    "semanticMatches": result.semanticMatches.map { mcpSnippetJSONObject(snippet: $0) },
  ]
}

/// 文字列の一致の種類を、ツールの結果に書く名前にする。
func mcpKeywordMatchKindText(kind: SnippetKeywordMatchKind) -> String {
  switch kind {
  case .keywordExact:
    "keywordExact"
  case .keywordPrefix:
    "keywordPrefix"
  case .titleOrBody:
    "titleOrBody"
  }
}

/// `create_snippet` で作ったスニペット。
func createSnippetTool(arguments: [String: Any], client: MCPClient, environment: MCPServerEnvironment) throws -> Snippet {
  let body = try mcpStringArgument(arguments: arguments, name: "body") ?? ""
  try validateSnippetBody(body: body)
  let snippet = Snippet(body: body)
  snippet.title = try mcpStringArgument(arguments: arguments, name: "title").flatMap { mcpOptionalText(text: $0) }
  snippet.keyword = try mcpStringArgument(arguments: arguments, name: "keyword").flatMap { mcpOptionalText(text: $0) }
  snippet.language = try mcpStringArgument(arguments: arguments, name: "language").flatMap { mcpOptionalText(text: $0) }
  try validateKeywordIsUnique(keyword: snippet.keyword, ownerID: snippet.id, modelContext: environment.modelContext)
  snippet.createdAt = environment.now()
  snippet.updatedAt = snippet.createdAt
  snippet.createdByKind = snippetAuthorKindMCP
  snippet.updatedByKind = snippetAuthorKindMCP
  snippet.createdByClientName = client.name
  snippet.updatedByClientName = client.name
  environment.modelContext.insert(snippet)
  try saveSnippetChanges(environment: environment)
  return snippet
}

/// `update_snippet` で更新したスニペット。検査に通るまでスニペットを書き換えない。
func updateSnippetTool(arguments: [String: Any], client: MCPClient, environment: MCPServerEnvironment) throws -> Snippet {
  let snippet = try fetchSnippetArgument(arguments: arguments, modelContext: environment.modelContext)
  let body = try mcpStringArgument(arguments: arguments, name: "body")
  let title = try mcpStringArgument(arguments: arguments, name: "title")
  let keyword = try mcpStringArgument(arguments: arguments, name: "keyword")
  let language = try mcpStringArgument(arguments: arguments, name: "language")
  if let body {
    try validateSnippetBody(body: body)
  }
  if let keyword {
    try validateKeywordIsUnique(keyword: mcpOptionalText(text: keyword), ownerID: snippet.id, modelContext: environment.modelContext)
  }
  if let body {
    snippet.body = body
  }
  if let title {
    snippet.title = mcpOptionalText(text: title)
  }
  if let keyword {
    snippet.keyword = mcpOptionalText(text: keyword)
  }
  if let language {
    snippet.language = mcpOptionalText(text: language)
  }
  snippet.updatedAt = environment.now()
  snippet.updatedByKind = snippetAuthorKindMCP
  snippet.updatedByClientName = client.name
  try saveSnippetChanges(environment: environment)
  return snippet
}

/// `delete_snippet` の結果。
///
/// 設定で確認を求めている時は、依頼元のクライアント名・理由・スニペットを確認に出し、許可された時だけ消す。
/// 確認を待つ間に同じスニペットが消えていることがあるため、許可の後にスニペットを読み直す。
/// 確認を待つ間にスニペットが更新されていたら、ユーザーが確かめた内容と違うものを消さないよう、消さずにツールのエラーを返す。
func deleteSnippetTool(arguments: [String: Any], client: MCPClient, environment: MCPServerEnvironment) async throws -> [String: Any] {
  let snippet = try fetchSnippetArgument(arguments: arguments, modelContext: environment.modelContext)
  let reason = try mcpRequiredStringArgument(arguments: arguments, name: "reason")
  let confirmedUpdatedAt = snippet.updatedAt
  let confirmedBody = snippet.body
  if environment.requiresDeletionConfirmation() {
    let isApproved = await environment.confirmSnippetDeletion(
      SnippetDeletionRequest(clientName: client.name, reason: reason, snippet: snippet, receivedAt: environment.now())
    )
    guard isApproved else {
      throw MCPToolError(description: "The user did not approve deleting the snippet. It was not deleted.")
    }
  }
  // 確認を待つ間にほかのコンテキストで保存された更新を読むため、読み込み済みのモデルを持たない新しいコンテキストで読み直す。
  let deletionModelContext = ModelContext(environment.modelContext.container)
  let approvedSnippet = try fetchSnippetArgument(arguments: arguments, modelContext: deletionModelContext)
  guard approvedSnippet.updatedAt == confirmedUpdatedAt, approvedSnippet.body == confirmedBody else {
    throw MCPToolError(description: "The snippet was changed while waiting for the user's confirmation. It was not deleted. Call delete_snippet again if it should still be deleted.")
  }
  // 削除して保存した後のモデルの属性は読めないため、先に識別子を取っておく。
  let deletedSnippetID = approvedSnippet.id.uuidString
  deletionModelContext.delete(approvedSnippet)
  try deletionModelContext.save()
  environment.snippetsDidChange()
  return ["deletedSnippetID": deletedSnippetID]
}

/// スニペットの変更を保存し、意味検索のベクトルの作り直しを頼む (`documents/PROJECT.md`「検索」)。
///
/// ベクトルの作成は本文の長さの分だけ時間が掛かるため、ここでは作らず、ほかのスレッドで作り直してもらう (`MCPServerController.requestSnippetEmbeddingRefresh()`)。
func saveSnippetChanges(environment: MCPServerEnvironment) throws {
  try environment.modelContext.save()
  environment.snippetsDidChange()
}
