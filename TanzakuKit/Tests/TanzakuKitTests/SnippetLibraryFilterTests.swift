import Foundation
import SwiftData
import Testing

@testable import TanzakuKit

/// 一覧の絞り込み (`snippetMatchesLibraryFilter` / `filteredSnippets`) を確かめる。
struct SnippetLibraryFilterTests {
  @Test("すべて・AI エージェントが追加・フォルダ・タグで絞り込む")
  func filterMatchesSnippets() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let folder = Folder(name: "dummy-folder")
    modelContext.insert(folder)
    let tag = SchemaV1.Tag(name: "dummy-tag")
    modelContext.insert(tag)
    let userSnippet = Snippet(body: "echo user")
    modelContext.insert(userSnippet)
    userSnippet.folder = folder
    let agentSnippet = Snippet(body: "echo agent")
    modelContext.insert(agentSnippet)
    agentSnippet.createdByKind = "mcp"
    agentSnippet.tags = [tag]
    let updatedByAgentSnippet = Snippet(body: "echo updated by agent")
    modelContext.insert(updatedByAgentSnippet)
    updatedByAgentSnippet.updatedByKind = "mcp"
    let snippets = [userSnippet, agentSnippet, updatedByAgentSnippet]

    #expect(snippets.filter { snippetMatchesLibraryFilter(snippet: $0, filter: .all) }.map(\.id) == snippets.map(\.id))
    #expect(snippets.filter { snippetMatchesLibraryFilter(snippet: $0, filter: .addedByAgent) }.map(\.id) == [agentSnippet.id])
    #expect(snippets.filter { snippetMatchesLibraryFilter(snippet: $0, filter: .folder(folderID: folder.id)) }.map(\.id) == [userSnippet.id])
    #expect(snippets.filter { snippetMatchesLibraryFilter(snippet: $0, filter: .tag(tagID: tag.id)) }.map(\.id) == [agentSnippet.id])
    #expect(snippets.filter { snippetMatchesLibraryFilter(snippet: $0, filter: .folder(folderID: UUID())) }.isEmpty)
  }

  @Test("検索欄が空なら渡したスニペットを、並びを保って絞り込みに合うものだけ返す", arguments: ["", "  "])
  func emptyQueryReturnsFilteredSnippetsInGivenOrder(query: String) throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let newerSnippet = Snippet(body: "echo newer")
    modelContext.insert(newerSnippet)
    let agentSnippet = Snippet(body: "echo agent")
    agentSnippet.createdByKind = "mcp"
    modelContext.insert(agentSnippet)
    let olderSnippet = Snippet(body: "echo older")
    modelContext.insert(olderSnippet)
    let snippets = [newerSnippet, agentSnippet, olderSnippet]

    #expect(
      try filteredSnippets(query: query, filter: .all, snippets: snippets, modelContext: modelContext, embedder: nil).map(\.id)
        == [newerSnippet.id, agentSnippet.id, olderSnippet.id]
    )
    #expect(
      try filteredSnippets(query: query, filter: .addedByAgent, snippets: snippets, modelContext: modelContext, embedder: nil).map(\.id)
        == [agentSnippet.id]
    )
  }

  @Test("検索欄に入力があれば、文字列で一致したものの後に意味検索で見つかったものを続け、絞り込みに合うものだけ返す")
  func queryReturnsKeywordMatchesThenSemanticMatches() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let folder = Folder(name: "dummy-folder")
    modelContext.insert(folder)
    let keywordMatchedSnippet = Snippet(body: "echo dummy")
    keywordMatchedSnippet.keyword = "query"
    modelContext.insert(keywordMatchedSnippet)
    keywordMatchedSnippet.folder = folder
    let semanticMatchedSnippet = Snippet(body: "near dummy")
    modelContext.insert(semanticMatchedSnippet)
    semanticMatchedSnippet.folder = folder
    let otherFolderSnippet = Snippet(body: "other folder dummy")
    modelContext.insert(otherFolderSnippet)
    let vectorsByText: [String: [Float]] = ["query": [1, 0, 0], "near dummy": [1, 0.1, 0], "other folder dummy": [1, 0.2, 0]]
    let embedder = SnippetTextEmbedder(modelIdentifier: "dummy-model") { vectorsByText[$0] ?? [0, 0, 1] }
    try updateSnippetEmbeddings(modelContext: modelContext, embedder: embedder)

    #expect(
      try filteredSnippets(
        query: "query", filter: .folder(folderID: folder.id), snippets: [keywordMatchedSnippet, semanticMatchedSnippet, otherFolderSnippet],
        modelContext: modelContext, embedder: embedder
      ).map(\.id) == [keywordMatchedSnippet.id, semanticMatchedSnippet.id]
    )
  }

  @Test("意味検索は絞り込みの中から選ぶため、絞り込みの外に意味の近いものが上限より多くあっても、絞り込みの中のものを返す")
  func semanticMatchesAreChosenWithinFilter() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let folder = Folder(name: "dummy-folder")
    modelContext.insert(folder)
    let outsideSnippets = (0..<4).map { index in
      let snippet = Snippet(body: "outside dummy \(index)")
      modelContext.insert(snippet)
      return snippet
    }
    let insideSnippet = Snippet(body: "inside dummy")
    modelContext.insert(insideSnippet)
    insideSnippet.folder = folder
    var vectorsByText: [String: [Float]] = ["query": [1, 0, 0], "inside dummy": [1, 0.5, 0]]
    for index in 0..<4 {
      vectorsByText["outside dummy \(index)"] = [1, 0.1, 0]
    }
    let embedder = SnippetTextEmbedder(modelIdentifier: "dummy-model") { [vectorsByText] in vectorsByText[$0] ?? [0, 0, 1] }
    try updateSnippetEmbeddings(modelContext: modelContext, embedder: embedder)

    #expect(
      try filteredSnippets(
        query: "query", filter: .folder(folderID: folder.id), snippets: outsideSnippets + [insideSnippet], modelContext: modelContext,
        embedder: embedder
      ).map(\.id) == [insideSnippet.id]
    )
  }
}
