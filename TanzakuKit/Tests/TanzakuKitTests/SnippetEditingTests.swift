import Foundation
import SwiftData
import Testing

@testable import TanzakuKit

/// 編集画面の保存 (`saveEditedSnippet(snippet:modelContext:now:)`)・タグとフォルダの作成・削除を確かめる。
struct SnippetEditingTests {
  @Test("空欄のタイトルとキーワードは無しにし、前後の空白を除き、更新した主体と日時を入れて保存する")
  func savesNormalizedSnippet() throws {
    let modelContainer = try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none)
    let modelContext = ModelContext(modelContainer)
    let snippet = Snippet(body: "echo dummy")
    snippet.title = "  "
    snippet.keyword = " ;dummy \n"
    snippet.updatedByKind = "mcp"
    snippet.updatedByClientName = "dummy-client"
    modelContext.insert(snippet)
    let now = Date(timeIntervalSince1970: 1_000)

    try saveEditedSnippet(snippet: snippet, modelContext: modelContext, now: now)

    #expect(snippet.title == nil)
    #expect(snippet.keyword == ";dummy")
    #expect(snippet.updatedAt == now)
    #expect(snippet.updatedByKind == "user")
    #expect(snippet.updatedByClientName == nil)
    #expect(!modelContext.hasChanges)
    #expect(try ModelContext(modelContainer).fetchCount(FetchDescriptor<Snippet>()) == 1)
  }

  @Test("本文が空なら保存しない")
  func emptyBodyIsNotSaved() throws {
    let modelContainer = try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none)
    let modelContext = ModelContext(modelContainer)
    let snippet = Snippet(body: " \n")
    modelContext.insert(snippet)

    #expect(throws: SnippetValidationError.emptyBody) {
      try saveEditedSnippet(snippet: snippet, modelContext: modelContext, now: .now)
    }
    #expect(try ModelContext(modelContainer).fetchCount(FetchDescriptor<Snippet>()) == 0)
  }

  @Test("別のスニペットと同じキーワードなら保存しない")
  func duplicatedKeywordIsNotSaved() throws {
    let modelContainer = try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none)
    let modelContext = ModelContext(modelContainer)
    let existingSnippet = Snippet(body: "echo dummy")
    existingSnippet.keyword = ";dummy"
    modelContext.insert(existingSnippet)
    try modelContext.save()
    let snippet = Snippet(body: "echo another dummy")
    snippet.keyword = ";dummy "
    modelContext.insert(snippet)

    #expect(throws: SnippetValidationError.keywordAlreadyUsed(keyword: ";dummy")) {
      try saveEditedSnippet(snippet: snippet, modelContext: modelContext, now: .now)
    }
    #expect(try ModelContext(modelContainer).fetchCount(FetchDescriptor<Snippet>()) == 1)
  }

  @Test("同じ名前のタグ・フォルダは作り直さず、空白だけの名前は作らない")
  func findOrInsertReusesSameName() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))

    let tag = try findOrInsertTag(name: " shell ", modelContext: modelContext)
    let sameTag = try findOrInsertTag(name: "shell", modelContext: modelContext)
    let folder = try findOrInsertFolder(name: "開発環境", modelContext: modelContext)
    let sameFolder = try findOrInsertFolder(name: "開発環境 ", modelContext: modelContext)

    #expect(tag?.name == "shell")
    #expect(tag?.id == sameTag?.id)
    #expect(folder?.id == sameFolder?.id)
    #expect(try findOrInsertTag(name: " ", modelContext: modelContext) == nil)
    #expect(try findOrInsertFolder(name: "", modelContext: modelContext) == nil)
    #expect(try modelContext.fetchCount(FetchDescriptor<SchemaV1.Tag>()) == 1)
    #expect(try modelContext.fetchCount(FetchDescriptor<Folder>()) == 1)
  }

  @Test("スニペットを消すと、その意味検索のベクトルとスニペットグループの項目も消え、ほかのスニペットは残る")
  func deleteSnippetsRemovesEmbeddingsAndGroupItems() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let deletedSnippet = Snippet(body: "echo deleted")
    let keptSnippet = Snippet(body: "echo kept")
    modelContext.insert(deletedSnippet)
    modelContext.insert(keptSnippet)
    let snippetGroup = SnippetGroup(name: "dummy-group")
    modelContext.insert(snippetGroup)
    replaceSnippetGroupItems(snippetGroup: snippetGroup, snippets: [deletedSnippet, keptSnippet], modelContext: modelContext)
    for snippet in [deletedSnippet, keptSnippet] {
      modelContext.insert(SnippetEmbedding(snippetID: snippet.id, modelIdentifier: "dummy-model", sourceHash: "dummy-hash", vector: Data()))
    }
    try modelContext.save()

    try deleteSnippets(snippets: [deletedSnippet], modelContext: modelContext)

    #expect(try modelContext.fetch(FetchDescriptor<Snippet>()).map(\.body) == ["echo kept"])
    #expect(try modelContext.fetch(FetchDescriptor<SnippetEmbedding>()).map(\.snippetID) == [keptSnippet.id])
    #expect(try modelContext.fetch(FetchDescriptor<SnippetGroupItem>()).compactMap(\.snippet?.id) == [keptSnippet.id])
  }
}
