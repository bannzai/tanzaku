import Foundation
import SwiftData
import Testing

@testable import TanzakuKit

/// Jev による意味検索の並べ替え (`JevSnippetRerank.swift`) を、API をスタブにして確かめる。値はすべて偽の値 (`.claude/rules/snippet-content-handling.md`)。
@MainActor
struct JevSnippetRerankTests {
  /// テスト用の偽の API キー。
  private let dummyAPIKey = "dummy-api-key-for-test"

  /// スニペットをストアに入れ、`vector` を意味検索のベクトルとして保存する。
  private func insertSnippet(modelContext: ModelContext, body: String, keyword: String? = nil) -> Snippet {
    let snippet = Snippet(body: body)
    snippet.keyword = keyword
    modelContext.insert(snippet)
    return snippet
  }

  /// テキストごとに決めたベクトルを返す偽の埋め込み。決めていないテキストは原点から離れた別の向きにする。
  private func lookupEmbedder(vectorsByText: [String: [Float]]) -> SnippetTextEmbedder {
    SnippetTextEmbedder(modelIdentifier: "dummy-model") { text in
      vectorsByText[text] ?? [0, 0, 1]
    }
  }

  /// 要求の本文から、候補の番号ごとの答えを返すスタブの応答を作る。
  private func jevResponse(noulsByQuestionID: [String: Double], statusCode: Int = 200) throws -> (Data, URLResponse) {
    (
      try JSONSerialization.data(withJSONObject: [
        "model": "jev-dummy",
        "answers": noulsByQuestionID.mapValues { ["type": "noul", "noul": $0] },
        "usage": ["input_tokens": 1, "output_tokens": 1],
      ]),
      HTTPURLResponse(url: jevAPIEndpoint, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    )
  }

  /// 要求の本文の JSON。
  private func jevRequestBody(request: URLRequest) throws -> [String: Any] {
    // #require の中に #require を書くとマクロの展開が再帰になりビルドできないため、本文を先に取り出す。
    let httpBody = try #require(request.httpBody)
    return try #require(try JSONSerialization.jsonObject(with: httpBody) as? [String: Any])
  }

  @Test("キーが無い時は Jev を呼ばず、今の意味検索 (埋め込み + しきい値) と同じ結果を返す")
  func noAPIKeyDoesNotCallJev() async throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let nearSnippet = insertSnippet(modelContext: modelContext, body: "near dummy")
    _ = insertSnippet(modelContext: modelContext, body: "far dummy")
    let embedder = lookupEmbedder(vectorsByText: ["query": [1, 0, 0], "near dummy": [1, 0, 0], "far dummy": [0, 1, 0]])
    try updateSnippetEmbeddings(modelContext: modelContext, embedder: embedder)
    var requestCount = 0

    let result = try await searchSnippets(
      query: "query",
      modelContext: modelContext,
      embedder: embedder,
      jevAPIKey: nil,
      sendJevRequest: { _ in
        requestCount += 1
        return try jevResponse(noulsByQuestionID: [:])
      },
      onJevError: { _ in }
    )

    #expect(requestCount == 0)
    #expect(result.semanticMatches.map(\.id) == [nearSnippet.id])
    #expect(result.semanticMatches.map(\.id) == (try searchSnippets(query: "query", modelContext: modelContext, embedder: embedder)).semanticMatches.map(\.id))
  }

  @Test("Jev が当てはまると答えた候補だけを、答えの大きい順に意味検索の結果にする。文字列で一致したものは候補に入れない")
  func jevAnswersReorderSemanticMatches() async throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let nearSnippet = insertSnippet(modelContext: modelContext, body: "near dummy")
    let farSnippet = insertSnippet(modelContext: modelContext, body: "far dummy")
    let keywordSnippet = insertSnippet(modelContext: modelContext, body: "keyword dummy", keyword: "query")
    let embedder = lookupEmbedder(vectorsByText: [
      "query": [1, 0, 0], "near dummy": [1, 0, 0], "far dummy": [0, 1, 0], "query\nkeyword dummy": [1, 0, 0],
    ])
    try updateSnippetEmbeddings(modelContext: modelContext, embedder: embedder)
    var candidateTexts: [String] = []

    let result = try await searchSnippets(
      query: "query",
      modelContext: modelContext,
      embedder: embedder,
      jevAPIKey: dummyAPIKey,
      sendJevRequest: { request in
        let snippetsByQuestionID = try #require((try jevRequestBody(request: request)["state"] as? [String: Any])?["snippets"] as? [String: String])
        candidateTexts = snippetsByQuestionID.keys.sorted().compactMap { snippetsByQuestionID[$0] }
        // 類似度の順の候補 1 (near) を「いいえ」、候補 2 (far) を「はい」にし、類似度ではなく答えで並ぶことを確かめる。
        return try jevResponse(noulsByQuestionID: ["snippet_1": 0.2, "snippet_2": 0.9])
      },
      onJevError: { error in
        Issue.record("Unexpected Jev error: \(error)")
      }
    )

    #expect(candidateTexts == ["near dummy", "far dummy"])
    #expect(result.semanticMatches.map(\.id) == [farSnippet.id])
    #expect(result.keywordMatches.map(\.snippet.id) == [keywordSnippet.id])
    #expect(!result.semanticMatches.map(\.id).contains(nearSnippet.id))
  }

  @Test("Jev の要求が失敗した時 (通信の失敗・2xx 以外の状態コード) は onJevError を呼び、今の意味検索と同じ結果に戻る")
  func jevFailureFallsBackToEmbeddingSearch() async throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let nearSnippet = insertSnippet(modelContext: modelContext, body: "near dummy")
    _ = insertSnippet(modelContext: modelContext, body: "far dummy")
    let embedder = lookupEmbedder(vectorsByText: ["query": [1, 0, 0], "near dummy": [1, 0, 0], "far dummy": [0, 1, 0]])
    try updateSnippetEmbeddings(modelContext: modelContext, embedder: embedder)
    let failingRequests: [(URLRequest) async throws -> (Data, URLResponse)] = [
      { _ in
        throw URLError(.notConnectedToInternet)
      },
      { _ in try self.jevResponse(noulsByQuestionID: [:], statusCode: 401) },
      { _ in (Data("not json".utf8), HTTPURLResponse(url: jevAPIEndpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!) },
    ]

    for sendJevRequest in failingRequests {
      var errors: [Error] = []
      let result = try await searchSnippets(
        query: "query",
        modelContext: modelContext,
        embedder: embedder,
        jevAPIKey: dummyAPIKey,
        sendJevRequest: sendJevRequest,
        onJevError: { errors.append($0) }
      )

      #expect(errors.count == 1)
      #expect(result.semanticMatches.map(\.id) == [nearSnippet.id])
    }
  }

  @Test("2xx 以外の状態コードのエラーの説明には、状態コードだけを入れ API キーを入れない")
  func jevRequestErrorDescriptionHasNoAPIKey() async throws {
    var errors: [Error] = []
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    _ = insertSnippet(modelContext: modelContext, body: "near dummy")
    let embedder = lookupEmbedder(vectorsByText: ["query": [1, 0, 0], "near dummy": [1, 0, 0]])
    try updateSnippetEmbeddings(modelContext: modelContext, embedder: embedder)

    _ = try await searchSnippets(
      query: "query",
      modelContext: modelContext,
      embedder: embedder,
      jevAPIKey: dummyAPIKey,
      sendJevRequest: { _ in try self.jevResponse(noulsByQuestionID: [:], statusCode: 401) },
      onJevError: { errors.append($0) }
    )

    #expect(errors.map { String(describing: $0) } == ["Jev request failed (HTTP status 401)"])
    #expect(!errors.map { String(describing: $0) }.joined().contains(dummyAPIKey))
  }

  @Test("要求は API キーを Authorization ヘッダーにだけ入れ、検索語と候補のテキストの秘匿情報らしい文字列を伏せ、候補のテキストを先頭だけにする")
  func jevRerankRequestMasksAndTruncates() throws {
    let request = try jevRerankRequest(
      query: "export API_TOKEN=dummy-token-for-test",
      candidateTexts: ["curl -H 'Authorization: Bearer dummybearertokenfortest0123' https://example.com", String(repeating: "a", count: 300)],
      apiKey: dummyAPIKey
    )
    let body = try jevRequestBody(request: request)
    let state = try #require(body["state"] as? [String: Any])
    let snippetsByQuestionID = try #require(state["snippets"] as? [String: String])

    #expect(request.url == jevAPIEndpoint)
    #expect(request.httpMethod == "POST")
    #expect(request.timeoutInterval == jevRequestTimeoutSeconds)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(dummyAPIKey)")
    #expect(!String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains(dummyAPIKey))
    #expect(body["model"] as? String == jevModelName)
    #expect(state["query"] as? String == "export API_TOKEN=[REDACTED]")
    #expect(snippetsByQuestionID["snippet_1"] == "curl -H 'Authorization: Bearer [REDACTED]' https://example.com")
    #expect(snippetsByQuestionID["snippet_2"]?.count == jevRerankCandidateMaxLength)
    #expect(Set((body["questions"] as? [String: Any])?.keys.map { $0 } ?? []) == ["snippet_1", "snippet_2"])
  }

  @Test("数字を含まない長い英字だけの文字列は伏せず、文字数が増えても短い時間で終わる")
  func snippetTextMaskingSecretsHandlesLongLetterRun() {
    let longLetterRun = String(repeating: "a", count: 100_000)
    let startedAt = Date.now

    let maskedText = snippetTextMaskingSecrets(text: longLetterRun + " dummy0123456789dummy0123456789dummy")

    #expect(maskedText == longLetterRun + " [REDACTED]")
    // 走査が文字数の二乗になると 10 万文字で数十秒かかるため、それより十分短い上限にした。
    #expect(Date.now.timeIntervalSince(startedAt) < 2)
  }

  @Test("秘匿情報らしい文字列を伏せ、ふつうの文章・コマンド・ファイルのパスは残す")
  func snippetTextMaskingSecretsMasksOnlySecretLikeText() {
    let cases: [(text: String, maskedText: String)] = [
      ("password: dummy-password", "password: [REDACTED]"),
      ("GITHUB_TOKEN=\"dummy-token\"", "GITHUB_TOKEN=\"[REDACTED]\""),
      ("PASSWORD=\"dummy secret phrase\" next", "PASSWORD=\"[REDACTED]\" next"),
      ("{\"password\":\"dummy-password\",\"user\":\"dummy\"}", "{\"password\":\"[REDACTED]\",\"user\":\"dummy\"}"),
      ("api_key: 'dummy key value'", "api_key: '[REDACTED]'"),
      ("password: \"dummy unclosed value\nnext line", "password: \"[REDACTED]\nnext line"),
      ("PASSWORD=dummy,secret next", "PASSWORD=[REDACTED] next"),
      ("curl -H 'Authorization: Basic ZHVtbXk6eA==' https://example.com", "curl -H 'Authorization: Basic [REDACTED]' https://example.com"),
      (#"{"password":"dummy\"remaining-secret"}"#, #"{"password":"[REDACTED]"}"#),
      ("https://dummyuser:dummypass@example.com/repo.git", "https://[REDACTED]@example.com/repo.git"),
      ("sk-dummyDummyDummyDummy1234", "[REDACTED]"),
      // 秘匿情報の検査 (コミット前の hook・secret scanning) に本物と取り違えられないよう、偽の値を分けて書いてつなぐ。
      ("AKIA" + "DUMMYDUMMY123456", "[REDACTED]"),
      ("-----BEGIN RSA " + "PRIVATE KEY-----\ndummy\n-----END RSA " + "PRIVATE KEY-----", "[REDACTED]"),
      ("value dummy0123456789dummy0123456789dummy end", "value [REDACTED] end"),
      ("git log --oneline -20", "git log --oneline -20"),
      ("/Users/dummy/worktrees/dummy/project-issue-63-64/documents", "/Users/dummy/worktrees/dummy/project-issue-63-64/documents"),
      ("basic usage of the command", "basic usage of the command"),
      ("トークンを更新する手順", "トークンを更新する手順"),
    ]
    for testCase in cases {
      #expect(snippetTextMaskingSecrets(text: testCase.text) == testCase.maskedText)
    }
  }
}
