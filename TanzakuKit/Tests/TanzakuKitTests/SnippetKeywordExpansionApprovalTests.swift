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
    #expect(fetchedSnippet.isMCPUpdateApproved)
    #expect(!snippetIsAwaitingKeywordExpansionApproval(snippet: fetchedSnippet))
    #expect(fetchedSnippet.updatedAt == updatedAt)
    #expect(fetchedSnippet.updatedByKind == snippetAuthorKindMCP)
    #expect(fetchedSnippet.updatedByClientName == "dummy-client")
  }
}
