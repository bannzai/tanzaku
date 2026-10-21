import Foundation
import SwiftData
import Testing

@testable import TanzakuKit

/// MCP のクライアントが作成・更新したスニペットの承認待ちの判定と、承認を確かめる。
struct SnippetKeywordExpansionApprovalTests {
  @Test("更新した主体が MCP で承認していないスニペットだけを承認待ちにする")
  func awaitsApprovalOnlyForUnapprovedMCPUpdate() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let userSnippet = Snippet(body: "echo dummy-user")
    let mcpSnippet = Snippet(body: "echo dummy-mcp")
    mcpSnippet.updatedByKind = snippetAuthorKindMCP
    // ユーザーが編集画面で保存した後のスニペットは、承認の属性が false のままでも更新した主体が user になる。
    let userSnippetCreatedByMCP = Snippet(body: "echo dummy-edited")
    userSnippetCreatedByMCP.createdByKind = snippetAuthorKindMCP
    modelContext.insert(userSnippet)
    modelContext.insert(mcpSnippet)
    modelContext.insert(userSnippetCreatedByMCP)

    #expect(!snippetIsAwaitingKeywordExpansionApproval(snippet: userSnippet))
    #expect(snippetIsAwaitingKeywordExpansionApproval(snippet: mcpSnippet))
    #expect(!snippetIsAwaitingKeywordExpansionApproval(snippet: userSnippetCreatedByMCP))
  }

  @Test("承認すると保存され、更新日時と更新の主体は変わらず、何度承認しても承認済みのまま")
  func approvalKeepsUpdateHistory() throws {
    let container = try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none)
    let modelContext = ModelContext(container)
    let updatedAt = Date(timeIntervalSince1970: 1_000)
    let snippet = Snippet(body: "echo dummy")
    snippet.updatedAt = updatedAt
    snippet.updatedByKind = snippetAuthorKindMCP
    snippet.updatedByClientName = "dummy-client"
    modelContext.insert(snippet)
    try modelContext.save()

    try approveSnippetKeywordExpansion(snippet: snippet, modelContext: modelContext)
    try approveSnippetKeywordExpansion(snippet: snippet, modelContext: modelContext)

    let fetchedSnippet = try #require(try ModelContext(container).fetch(FetchDescriptor<Snippet>()).first)
    #expect(fetchedSnippet.mcpApprovedContentHash == snippetKeywordExpansionContentHash(snippet: fetchedSnippet))
    #expect(!snippetIsAwaitingKeywordExpansionApproval(snippet: fetchedSnippet))
    #expect(fetchedSnippet.updatedAt == updatedAt)
    #expect(fetchedSnippet.updatedByKind == snippetAuthorKindMCP)
    #expect(fetchedSnippet.updatedByClientName == "dummy-client")
  }

  @Test("承認した後に本文かキーワードが変わったスニペットは、承認の値が残っていても承認待ちに戻る (別の端末の MCP の更新が同期で届いた時)")
  func contentChangedAfterApprovalAwaitsApprovalAgain() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let snippet = Snippet(body: "echo dummy-approved")
    snippet.keyword = ";tkw"
    snippet.updatedByKind = snippetAuthorKindMCP
    modelContext.insert(snippet)
    try approveSnippetKeywordExpansion(snippet: snippet, modelContext: modelContext)

    snippet.body = "echo dummy-synced-from-another-mac"
    #expect(snippetIsAwaitingKeywordExpansionApproval(snippet: snippet))

    snippet.body = "echo dummy-approved"
    snippet.keyword = ";tkw2"
    #expect(snippetIsAwaitingKeywordExpansionApproval(snippet: snippet))
  }

  @Test("同期で更新した主体が user と組み合わさっても、MCP の承認待ちの記録か見ていない本文があれば承認待ちにする")
  func userAuthorKindDoesNotBypassContentHash() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let snippet = Snippet(body: "")
    try applySnippetEdit(
      snippet: snippet,
      body: "echo dummy-saved-by-user",
      attachmentData: nil,
      attachmentContentType: nil,
      attachmentFileName: nil,
      title: "",
      keyword: ";tkw",
      language: nil,
      color: nil,
      folder: nil,
      tagNames: [],
      modelContext: modelContext,
      now: .now
    )
    #expect(snippet.updatedByKind == "user")
    #expect(!snippetIsAwaitingKeywordExpansionApproval(snippet: snippet))

    // 別の端末の MCP が書いた本文だけが届き、更新した主体と承認の記録はこの端末の保存のまま。
    snippet.body = "echo dummy-synced-from-another-mac"
    #expect(snippetIsAwaitingKeywordExpansionApproval(snippet: snippet))

    // 別の端末の MCP が書いた承認待ちの記録だけが届き、本文と更新した主体はこの端末の保存のまま。
    snippet.body = "echo dummy-saved-by-user"
    snippet.mcpApprovedContentHash = snippetMCPUnapprovedContentHash
    #expect(snippetIsAwaitingKeywordExpansionApproval(snippet: snippet))
  }

  @Test("キーワードと本文の境目だけが違う組み合わせは、別のハッシュになる")
  func contentHashSeparatesKeywordAndBody() {
    let snippet = Snippet(body: "c")
    snippet.keyword = "ab"
    let otherSnippet = Snippet(body: "bc")
    otherSnippet.keyword = "a"
    #expect(snippetKeywordExpansionContentHash(snippet: snippet) != snippetKeywordExpansionContentHash(snippet: otherSnippet))
  }
}
