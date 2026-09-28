import Foundation
import SwiftData
import TanzakuKit
import Testing

@testable import Tanzaku

/// 削除の確認に届いた依頼を記録し、決めた答えを返す偽の確認。
final class RecordingSnippetDeletionConfirmation {
  /// 確認に返す答え。
  var isApproved: Bool
  /// 確認に届いた依頼。
  var requests: [SnippetDeletionRequest] = []
  /// 確認を待つ間に起きること (ほかのリクエストによる更新など) を再現する処理。
  var whileConfirming: (SnippetDeletionRequest) -> Void = { _ in }

  /// 確認に返す答えを受け取る。
  init(isApproved: Bool) {
    self.isApproved = isApproved
  }
}

/// スニペットの変更の保存の後に、ベクトルの作り直しを頼まれた回数を数える。
final class SnippetChangeCounter {
  /// 頼まれた回数。
  var count = 0
}

/// `handleMCPHTTPRequest(request:environment:)` を、HTTP のリクエストを組み立てて呼び、認証とツールの入出力を確かめる。
struct MCPServerTests {
  /// テストの接続済みのクライアントのトークン。
  let clientToken = "dummy-token-for-test-client"
  /// テストの持ち主のいないトークン。
  let unboundToken = "dummy-token-for-test-unbound"

  /// メモリのストアと、偽のトークン・確認を持つ環境。`registeredClientName` を渡すとそのクライアントを接続済みにする。
  ///
  /// 既定は、ほとんどのテストが前提にする「接続済みのクライアントが 1 つあり、削除には確認を求め、確認は許可する」状態 (アプリの既定の設定と同じ)。
  /// ベクトルの作り直しを頼んだ回数を見ないテストは、どこからも読まない新しいカウンターで足りるため、既定はそれにする。
  func makeEnvironment(
    registeredClientName: String? = "Claude Code",
    requiresDeletionConfirmation: Bool = true,
    confirmation: RecordingSnippetDeletionConfirmation = RecordingSnippetDeletionConfirmation(isApproved: true),
    snippetChangeCounter: SnippetChangeCounter = SnippetChangeCounter()
  ) throws -> MCPServerEnvironment {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    var tokens: [MCPTokenOwner: String] = [.unbound: unboundToken]
    if let registeredClientName {
      let client = MCPClient(id: UUID(), name: registeredClientName, createdAt: Date(timeIntervalSince1970: 0))
      modelContext.insert(client)
      try modelContext.save()
      tokens[.client(id: client.id)] = clientToken
    }
    return MCPServerEnvironment(
      modelContext: modelContext,
      tokenStore: inMemoryMCPTokenStore(initialTokens: tokens),
      port: mcpServerPort,
      embedder: { nil },
      snippetsDidChange: {
        snippetChangeCounter.count += 1
      },
      requiresDeletionConfirmation: { requiresDeletionConfirmation },
      confirmSnippetDeletion: { request in
        confirmation.requests.append(request)
        confirmation.whileConfirming(request)
        return confirmation.isApproved
      },
      now: { Date(timeIntervalSince1970: 1000) }
    )
  }

  /// JSON-RPC のメッセージを本文にした POST のリクエスト。
  func makeRequest(message: [String: Any], token: String?, headers: [String: String] = [:]) throws -> MCPHTTPRequest {
    var requestHeaders = headers
    requestHeaders["content-type"] = "application/json"
    requestHeaders["authorization"] = token.map { "Bearer \($0)" }
    return MCPHTTPRequest(method: "POST", path: "/mcp", headers: requestHeaders, body: try JSONSerialization.data(withJSONObject: message))
  }

  /// `tools/call` のリクエスト。
  func makeToolCallRequest(name: String, arguments: [String: Any], token: String? = nil) throws -> MCPHTTPRequest {
    try makeRequest(
      message: ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": name, "arguments": arguments] as [String: Any]],
      token: token ?? clientToken
    )
  }

  /// レスポンスの本文の JSON。
  func responseJSON(response: MCPHTTPResponse) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: response.body) as? [String: Any])
  }

  /// `tools/call` の `result`。
  func toolResult(response: MCPHTTPResponse) throws -> [String: Any] {
    #expect(response.statusCode == 200)
    return try #require(try responseJSON(response: response)["result"] as? [String: Any])
  }

  /// ストアのスニペット。
  func fetchSnippets(environment: MCPServerEnvironment) throws -> [Snippet] {
    try environment.modelContext.fetch(FetchDescriptor<Snippet>())
  }

  /// ストアにスニペットを入れる。
  func insertSnippet(environment: MCPServerEnvironment, body: String, keyword: String? = nil) throws -> Snippet {
    let snippet = Snippet(body: body)
    snippet.keyword = keyword
    environment.modelContext.insert(snippet)
    try environment.modelContext.save()
    return snippet
  }

  @Test("トークンが無い・一致しないリクエストは 401 で拒否する")
  func rejectsMissingOrUnknownToken() async throws {
    let environment = try makeEnvironment()
    let message: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "tools/list"]

    let missingTokenResponse = await handleMCPHTTPRequest(request: try makeRequest(message: message, token: nil), environment: environment)
    let unknownTokenResponse = await handleMCPHTTPRequest(request: try makeRequest(message: message, token: "dummy-token-unknown"), environment: environment)

    #expect(missingTokenResponse.statusCode == 401)
    #expect(missingTokenResponse.headers["WWW-Authenticate"] != nil)
    #expect(unknownTokenResponse.statusCode == 401)
  }

  @Test("取り消したクライアントのトークンのリクエストは拒否する")
  func rejectsRevokedClientToken() async throws {
    let environment = try makeEnvironment()
    let request = try makeRequest(message: ["jsonrpc": "2.0", "id": 1, "method": "tools/list"], token: clientToken)
    #expect(await handleMCPHTTPRequest(request: request, environment: environment).statusCode == 200)

    let client = try #require(try environment.modelContext.fetch(FetchDescriptor<MCPClient>()).first)
    try revokeMCPClient(client: client, modelContext: environment.modelContext, tokenStore: environment.tokenStore)

    #expect(await handleMCPHTTPRequest(request: request, environment: environment).statusCode == 401)
    #expect(try environment.modelContext.fetchCount(FetchDescriptor<MCPClient>()) == 0)
  }

  @Test("持ち主のいないトークンの initialize で、名乗ったクライアントを登録してトークンをそのクライアントのものにする")
  func bindsUnboundTokenOnInitialize() async throws {
    let environment = try makeEnvironment(registeredClientName: nil)
    let request = try makeRequest(
      message: [
        "jsonrpc": "2.0", "id": 1, "method": "initialize",
        "params": ["protocolVersion": "2025-06-18", "capabilities": [String: Any](), "clientInfo": ["name": "claude-code", "title": "Claude Code", "version": "1.0.0"]] as [String: Any],
      ],
      token: unboundToken
    )

    let result = try toolResult(response: await handleMCPHTTPRequest(request: request, environment: environment))

    #expect(result["protocolVersion"] as? String == "2025-06-18")
    #expect((result["capabilities"] as? [String: Any])?["tools"] != nil)
    let client = try #require(try environment.modelContext.fetch(FetchDescriptor<MCPClient>()).first)
    #expect(client.name == "Claude Code")
    #expect(client.lastUsedAt == Date(timeIntervalSince1970: 1000))
    let tokens = try environment.tokenStore.loadTokens()
    #expect(tokens[.client(id: client.id)] == unboundToken)
    #expect(tokens[.unbound] == nil)
  }

  @Test("持ち主のいないトークンで、クライアント名を名乗らないリクエストは拒否する")
  func rejectsUnboundTokenWithoutClientInfo() async throws {
    let environment = try makeEnvironment(registeredClientName: nil)

    let response = await handleMCPHTTPRequest(
      request: try makeRequest(message: ["jsonrpc": "2.0", "id": 1, "method": "tools/list"], token: unboundToken),
      environment: environment
    )

    #expect(response.statusCode == 401)
    #expect(try environment.modelContext.fetchCount(FetchDescriptor<MCPClient>()) == 0)
  }

  @Test("initialize で受け付けない版を求められたら、受け付ける最も新しい版を返す")
  func negotiatesLegacyProtocolVersion() async throws {
    let environment = try makeEnvironment()
    let request = try makeRequest(
      message: ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2024-11-05", "clientInfo": ["name": "old-client"]] as [String: Any]],
      token: clientToken
    )

    #expect(try toolResult(response: await handleMCPHTTPRequest(request: request, environment: environment))["protocolVersion"] as? String == mcpLegacyProtocolVersions[0])
  }

  @Test("2026-07-28 の版のリクエストは、_meta の版とヘッダーが一致する時だけ受け付ける")
  func validatesModernRequestHeaders() async throws {
    let environment = try makeEnvironment()
    let message: [String: Any] = [
      "jsonrpc": "2.0", "id": 1, "method": "tools/list",
      "params": ["_meta": ["io.modelcontextprotocol/protocolVersion": "2026-07-28", "io.modelcontextprotocol/clientInfo": ["name": "Claude Code"]] as [String: Any]],
    ]

    let validResponse = await handleMCPHTTPRequest(
      request: try makeRequest(message: message, token: clientToken, headers: ["mcp-protocol-version": "2026-07-28", "mcp-method": "tools/list"]),
      environment: environment
    )
    let mismatchResponse = await handleMCPHTTPRequest(
      request: try makeRequest(message: message, token: clientToken, headers: ["mcp-protocol-version": "2026-07-28", "mcp-method": "tools/call"]),
      environment: environment
    )

    #expect(validResponse.statusCode == 200)
    #expect(mismatchResponse.statusCode == 400)
    #expect((try responseJSON(response: mismatchResponse)["error"] as? [String: Any])?["code"] as? Int == -32020)
  }

  @Test("受け付けない版の 2026-07-28 以降のリクエストは、受け付ける版を付けて 400 で返す")
  func rejectsUnsupportedModernProtocolVersion() async throws {
    let environment = try makeEnvironment()
    let message: [String: Any] = [
      "jsonrpc": "2.0", "id": 1, "method": "tools/list",
      "params": ["_meta": ["io.modelcontextprotocol/protocolVersion": "2099-01-01"]],
    ]

    let response = await handleMCPHTTPRequest(
      request: try makeRequest(message: message, token: clientToken, headers: ["mcp-protocol-version": "2099-01-01", "mcp-method": "tools/list"]),
      environment: environment
    )

    #expect(response.statusCode == 400)
    let error = try #require(try responseJSON(response: response)["error"] as? [String: Any])
    #expect(error["code"] as? Int == -32022)
    #expect((error["data"] as? [String: Any])?["supported"] as? [String] == mcpModernProtocolVersions + mcpLegacyProtocolVersions)
  }

  @Test("ほかのオリジンのリクエストは 403、POST 以外は 405、通知は 202 で返す")
  func handlesOriginMethodAndNotification() async throws {
    let environment = try makeEnvironment()
    let message: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "ping"]

    let forbiddenResponse = await handleMCPHTTPRequest(
      request: try makeRequest(message: message, token: clientToken, headers: ["origin": "https://example.com"]),
      environment: environment
    )
    let getResponse = await handleMCPHTTPRequest(
      request: MCPHTTPRequest(method: "GET", path: "/mcp", headers: ["authorization": "Bearer \(clientToken)"], body: Data()),
      environment: environment
    )
    let notificationResponse = await handleMCPHTTPRequest(
      request: try makeRequest(message: ["jsonrpc": "2.0", "method": "notifications/initialized"], token: clientToken),
      environment: environment
    )

    #expect(forbiddenResponse.statusCode == 403)
    #expect(getResponse.statusCode == 405)
    #expect(notificationResponse.statusCode == 202)
    #expect(notificationResponse.body.isEmpty)
  }

  @Test("tools/list で検索・取得・追加・更新・削除の 5 つのツールを返す")
  func listsTools() async throws {
    let environment = try makeEnvironment()

    let result = try toolResult(
      response: await handleMCPHTTPRequest(request: try makeRequest(message: ["jsonrpc": "2.0", "id": 1, "method": "tools/list"], token: clientToken), environment: environment)
    )

    #expect(
      (result["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
        == ["search_snippets", "get_snippet", "create_snippet", "update_snippet", "delete_snippet"]
    )
  }

  @Test("追加のツールは、作成・更新の主体に MCP のクライアント名を記録する")
  func createSnippetRecordsClientName() async throws {
    let environment = try makeEnvironment()

    let result = try toolResult(
      response: await handleMCPHTTPRequest(
        request: try makeToolCallRequest(name: "create_snippet", arguments: ["body": "echo dummy", "title": "Dummy", "keyword": "dm", "language": "shell"]),
        environment: environment
      )
    )

    #expect(result["isError"] as? Bool == false)
    let snippet = try #require(try fetchSnippets(environment: environment).first)
    #expect(snippet.body == "echo dummy")
    #expect(snippet.title == "Dummy")
    #expect(snippet.keyword == "dm")
    #expect(snippet.language == "shell")
    #expect(snippet.createdByKind == "mcp")
    #expect(snippet.createdByClientName == "Claude Code")
    #expect(snippet.updatedByKind == "mcp")
    #expect(snippet.updatedByClientName == "Claude Code")
    #expect(((result["structuredContent"] as? [String: Any])?["snippet"] as? [String: Any])?["id"] as? String == snippet.id.uuidString)
  }

  @Test("追加・更新・削除を保存した後に意味検索のベクトルの作り直しを頼み、検索と取得では頼まない")
  func requestsEmbeddingRefreshAfterChanges() async throws {
    let snippetChangeCounter = SnippetChangeCounter()
    let environment = try makeEnvironment(requiresDeletionConfirmation: false, snippetChangeCounter: snippetChangeCounter)

    let createResult = try toolResult(
      response: await handleMCPHTTPRequest(request: try makeToolCallRequest(name: "create_snippet", arguments: ["body": "echo dummy"]), environment: environment)
    )
    let snippetID = try #require(((createResult["structuredContent"] as? [String: Any])?["snippet"] as? [String: Any])?["id"] as? String)
    _ = await handleMCPHTTPRequest(request: try makeToolCallRequest(name: "search_snippets", arguments: ["query": "dummy"]), environment: environment)
    _ = await handleMCPHTTPRequest(request: try makeToolCallRequest(name: "get_snippet", arguments: ["id": snippetID]), environment: environment)
    #expect(snippetChangeCounter.count == 1)

    _ = await handleMCPHTTPRequest(
      request: try makeToolCallRequest(name: "update_snippet", arguments: ["id": snippetID, "body": "echo dummy updated"]),
      environment: environment
    )
    _ = await handleMCPHTTPRequest(
      request: try makeToolCallRequest(name: "delete_snippet", arguments: ["id": snippetID, "reason": "No longer used"]),
      environment: environment
    )

    #expect(snippetChangeCounter.count == 3)
    #expect(try fetchSnippets(environment: environment).isEmpty)
  }

  @Test("追加のツールは、空の本文と使われているキーワードをツールのエラーで返し、保存しない")
  func createSnippetValidates() async throws {
    let environment = try makeEnvironment()
    _ = try insertSnippet(environment: environment, body: "echo existing", keyword: "dm")

    let emptyBodyResult = try toolResult(
      response: await handleMCPHTTPRequest(request: try makeToolCallRequest(name: "create_snippet", arguments: ["body": "  \n"]), environment: environment)
    )
    let duplicateKeywordResult = try toolResult(
      response: await handleMCPHTTPRequest(
        request: try makeToolCallRequest(name: "create_snippet", arguments: ["body": "echo dummy", "keyword": "dm"]),
        environment: environment
      )
    )

    #expect(emptyBodyResult["isError"] as? Bool == true)
    #expect(duplicateKeywordResult["isError"] as? Bool == true)
    #expect(try fetchSnippets(environment: environment).count == 1)
  }

  @Test("検索のツールは、文字列で一致したスニペットを本文と一緒に返す")
  func searchSnippetsReturnsMatches() async throws {
    let environment = try makeEnvironment()
    let snippet = try insertSnippet(environment: environment, body: "docker compose up", keyword: "dcu")

    let result = try toolResult(
      response: await handleMCPHTTPRequest(request: try makeToolCallRequest(name: "search_snippets", arguments: ["query": "dcu"]), environment: environment)
    )

    let keywordMatches = try #require((result["structuredContent"] as? [String: Any])?["keywordMatches"] as? [[String: Any]])
    #expect(keywordMatches.count == 1)
    #expect(keywordMatches.first?["match"] as? String == "keywordExact")
    #expect((keywordMatches.first?["snippet"] as? [String: Any])?["id"] as? String == snippet.id.uuidString)
    #expect((keywordMatches.first?["snippet"] as? [String: Any])?["body"] as? String == "docker compose up")
  }

  @Test("取得のツールは id のスニペットを返し、無い id はツールのエラーにする")
  func getSnippet() async throws {
    let environment = try makeEnvironment()
    let snippet = try insertSnippet(environment: environment, body: "echo dummy")

    let foundResult = try toolResult(
      response: await handleMCPHTTPRequest(request: try makeToolCallRequest(name: "get_snippet", arguments: ["id": snippet.id.uuidString]), environment: environment)
    )
    let missingResult = try toolResult(
      response: await handleMCPHTTPRequest(request: try makeToolCallRequest(name: "get_snippet", arguments: ["id": UUID().uuidString]), environment: environment)
    )

    #expect(((foundResult["structuredContent"] as? [String: Any])?["snippet"] as? [String: Any])?["body"] as? String == "echo dummy")
    #expect(missingResult["isError"] as? Bool == true)
  }

  @Test("更新のツールは渡した属性だけを変え、空文字で消し、更新の主体に MCP のクライアント名を記録する")
  func updateSnippet() async throws {
    let environment = try makeEnvironment()
    let snippet = try insertSnippet(environment: environment, body: "echo dummy", keyword: "old")
    snippet.title = "Old title"

    let result = try toolResult(
      response: await handleMCPHTTPRequest(
        request: try makeToolCallRequest(name: "update_snippet", arguments: ["id": snippet.id.uuidString, "keyword": "new", "title": ""]),
        environment: environment
      )
    )

    #expect(result["isError"] as? Bool == false)
    #expect(snippet.body == "echo dummy")
    #expect(snippet.keyword == "new")
    #expect(snippet.title == nil)
    #expect(snippet.createdByKind == "user")
    #expect(snippet.updatedByKind == "mcp")
    #expect(snippet.updatedByClientName == "Claude Code")
    #expect(snippet.updatedAt == Date(timeIntervalSince1970: 1000))
  }

  @Test("削除のツールは、確認で許可された時だけ消し、確認に依頼元のクライアント名と理由を渡す")
  func deleteSnippetFollowsApproval() async throws {
    let confirmation = RecordingSnippetDeletionConfirmation(isApproved: true)
    let environment = try makeEnvironment(confirmation: confirmation)
    let snippet = try insertSnippet(environment: environment, body: "echo dummy")

    let result = try toolResult(
      response: await handleMCPHTTPRequest(
        request: try makeToolCallRequest(name: "delete_snippet", arguments: ["id": snippet.id.uuidString, "reason": "No longer used"]),
        environment: environment
      )
    )

    #expect(result["isError"] as? Bool == false)
    #expect(try fetchSnippets(environment: environment).isEmpty)
    #expect(confirmation.requests.map(\.clientName) == ["Claude Code"])
    #expect(confirmation.requests.map(\.reason) == ["No longer used"])
  }

  @Test("削除のツールは、確認で拒否された時は消さずにツールのエラーを返す")
  func deleteSnippetFollowsRejection() async throws {
    let confirmation = RecordingSnippetDeletionConfirmation(isApproved: false)
    let environment = try makeEnvironment(confirmation: confirmation)
    let snippet = try insertSnippet(environment: environment, body: "echo dummy")

    let result = try toolResult(
      response: await handleMCPHTTPRequest(
        request: try makeToolCallRequest(name: "delete_snippet", arguments: ["id": snippet.id.uuidString, "reason": "No longer used"]),
        environment: environment
      )
    )

    #expect(result["isError"] as? Bool == true)
    #expect(try fetchSnippets(environment: environment).map(\.id) == [snippet.id])
    #expect(confirmation.requests.count == 1)
  }

  @Test("削除のツールは、確認を待つ間にスニペットが更新されたら、許可されても消さずにツールのエラーを返す")
  func deleteSnippetRejectsChangeDuringConfirmation() async throws {
    let confirmation = RecordingSnippetDeletionConfirmation(isApproved: true)
    let environment = try makeEnvironment(confirmation: confirmation)
    let snippet = try insertSnippet(environment: environment, body: "echo dummy")
    confirmation.whileConfirming = { request in
      // ほかのリクエストが同じスニペットを更新して保存したことにする。
      let otherModelContext = ModelContext(environment.modelContext.container)
      let otherSnippet = try? otherModelContext.fetch(FetchDescriptor<Snippet>()).first { $0.id == request.snippet.id }
      otherSnippet?.body = "echo dummy updated"
      otherSnippet?.updatedAt = Date(timeIntervalSince1970: 2000)
      try? otherModelContext.save()
    }

    let result = try toolResult(
      response: await handleMCPHTTPRequest(
        request: try makeToolCallRequest(name: "delete_snippet", arguments: ["id": snippet.id.uuidString, "reason": "No longer used"]),
        environment: environment
      )
    )

    #expect(result["isError"] as? Bool == true)
    #expect(try fetchSnippets(environment: environment).map(\.id) == [snippet.id])
  }

  @Test("削除のツールは、確認を待つ間に依頼元のクライアントの接続が取り消されたら、許可されても消さない")
  func deleteSnippetRejectsRevokedClientDuringConfirmation() async throws {
    let confirmation = RecordingSnippetDeletionConfirmation(isApproved: true)
    let environment = try makeEnvironment(confirmation: confirmation)
    let snippet = try insertSnippet(environment: environment, body: "echo dummy")
    confirmation.whileConfirming = { request in
      let otherModelContext = ModelContext(environment.modelContext.container)
      if let client = try? otherModelContext.fetch(FetchDescriptor<MCPClient>()).first(where: { $0.id == request.clientID }) {
        try? revokeMCPClient(client: client, modelContext: otherModelContext, tokenStore: environment.tokenStore)
      }
    }

    let result = try toolResult(
      response: await handleMCPHTTPRequest(
        request: try makeToolCallRequest(name: "delete_snippet", arguments: ["id": snippet.id.uuidString, "reason": "No longer used"]),
        environment: environment
      )
    )

    #expect(result["isError"] as? Bool == true)
    #expect(try fetchSnippets(environment: environment).map(\.id) == [snippet.id])
  }

  @Test("検索のツールは、上限を超える長さのクエリをツールのエラーで返す")
  func searchSnippetsRejectsLongQuery() async throws {
    let environment = try makeEnvironment()

    let result = try toolResult(
      response: await handleMCPHTTPRequest(
        request: try makeToolCallRequest(name: "search_snippets", arguments: ["query": String(repeating: "a", count: mcpSearchMaximumQueryLength + 1)]),
        environment: environment
      )
    )

    #expect(result["isError"] as? Bool == true)
  }

  @Test("削除のツールは、設定で確認を切っていれば確認を出さずに消す")
  func deleteSnippetWithoutConfirmation() async throws {
    let confirmation = RecordingSnippetDeletionConfirmation(isApproved: false)
    let environment = try makeEnvironment(requiresDeletionConfirmation: false, confirmation: confirmation)
    let snippet = try insertSnippet(environment: environment, body: "echo dummy")

    let result = try toolResult(
      response: await handleMCPHTTPRequest(
        request: try makeToolCallRequest(name: "delete_snippet", arguments: ["id": snippet.id.uuidString, "reason": "No longer used"]),
        environment: environment
      )
    )

    #expect(result["isError"] as? Bool == false)
    #expect(try fetchSnippets(environment: environment).isEmpty)
    #expect(confirmation.requests.isEmpty)
  }

  @Test("削除のツールは理由が無ければ確認を出さずにツールのエラーを返す")
  func deleteSnippetRequiresReason() async throws {
    let confirmation = RecordingSnippetDeletionConfirmation(isApproved: true)
    let environment = try makeEnvironment(confirmation: confirmation)
    let snippet = try insertSnippet(environment: environment, body: "echo dummy")

    let result = try toolResult(
      response: await handleMCPHTTPRequest(request: try makeToolCallRequest(name: "delete_snippet", arguments: ["id": snippet.id.uuidString]), environment: environment)
    )

    #expect(result["isError"] as? Bool == true)
    #expect(try fetchSnippets(environment: environment).count == 1)
    #expect(confirmation.requests.isEmpty)
  }

  @Test("知らないツールは JSON-RPC のエラーで返す")
  func unknownToolIsProtocolError() async throws {
    let environment = try makeEnvironment()

    let response = await handleMCPHTTPRequest(request: try makeToolCallRequest(name: "unknown_tool", arguments: [:]), environment: environment)

    #expect((try responseJSON(response: response)["error"] as? [String: Any])?["code"] as? Int == -32602)
  }
}
