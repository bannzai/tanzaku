import Foundation
import SwiftData
import Testing

@testable import TanzakuKit

/// サイドバーの絞り込み (`filteredLibrarySnippets(snippets:filter:)`) を確かめる。
struct SnippetLibraryFilterTests {
  @Test("すべて・AI エージェントが追加・フォルダ・タグ・スニペットグループの条件で絞り込む")
  func filtersByEachCondition() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let folder = Folder(name: "開発環境")
    let tag = Tag(name: "shell")
    let snippetGroup = SnippetGroup(name: "dummy-group")
    let userSnippet = Snippet(body: "echo user")
    let agentSnippet = Snippet(body: "echo agent")
    agentSnippet.createdByKind = "mcp"
    agentSnippet.createdByClientName = "dummy-client"
    for model in [folder, tag, snippetGroup, userSnippet, agentSnippet] as [any PersistentModel] {
      modelContext.insert(model)
    }
    userSnippet.folder = folder
    agentSnippet.tags = [tag]
    replaceSnippetGroupItems(snippetGroup: snippetGroup, snippets: [agentSnippet, userSnippet], modelContext: modelContext)
    try modelContext.save()
    let snippets = [userSnippet, agentSnippet]

    #expect(filteredLibrarySnippets(snippets: snippets, filter: .allSnippets).map(\.body) == ["echo user", "echo agent"])
    #expect(filteredLibrarySnippets(snippets: snippets, filter: .addedByAgent).map(\.body) == ["echo agent"])
    #expect(filteredLibrarySnippets(snippets: snippets, filter: .folder(folder)).map(\.body) == ["echo user"])
    #expect(filteredLibrarySnippets(snippets: snippets, filter: .tag(tag)).map(\.body) == ["echo agent"])
    #expect(filteredLibrarySnippets(snippets: snippets, filter: .snippetGroup(snippetGroup)).map(\.body) == ["echo agent", "echo user"])
    #expect(!isSnippetInLibraryFilter(snippet: userSnippet, filter: .tag(tag)))
    #expect(isSnippetInLibraryFilter(snippet: userSnippet, filter: .snippetGroup(snippetGroup)))
  }
}
