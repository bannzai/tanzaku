import Foundation
import SwiftData
import Testing

@testable import TanzakuKit

/// `SchemaV1` の既定値と削除ルールが `documents/data-model.md` のとおりかを、インメモリのストアで確かめる。
struct SchemaV1Tests {
  @Test("Snippet は本文以外が既定値で作られる")
  func snippetDefaults() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let snippet = Snippet(body: "echo dummy")
    modelContext.insert(snippet)
    #expect(snippet.body == "echo dummy")
    #expect(snippet.title == nil)
    #expect(snippet.keyword == nil)
    #expect(snippet.language == nil)
    #expect(snippet.colorRawValue == nil)
    #expect(snippet.folder == nil)
    #expect(snippet.tags == [])
    #expect(snippet.groupItems == [])
    #expect(snippet.createdByKind == "user")
    #expect(snippet.updatedByKind == "user")
    #expect(snippet.createdByClientName == nil)
    #expect(snippet.updatedByClientName == nil)
  }

  @Test("保存したスニペットを別の ModelContext から読み出せる")
  func saveAndFetchSnippet() throws {
    let container = try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none)
    let writingContext = ModelContext(container)
    let snippet = Snippet(body: "echo dummy")
    snippet.title = "ダミーのタイトル"
    snippet.keyword = ";dummy"
    writingContext.insert(snippet)
    try writingContext.save()

    let fetchedSnippets = try ModelContext(container).fetch(FetchDescriptor<Snippet>())
    #expect(fetchedSnippets.map(\.id) == [snippet.id])
    #expect(fetchedSnippets.map(\.title) == ["ダミーのタイトル"])
    #expect(fetchedSnippets.map(\.keyword) == [";dummy"])
  }

  @Test("フォルダを消してもスニペットは残る")
  func deletingFolderKeepsSnippets() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let folder = Folder(name: "dummy-folder")
    let snippet = Snippet(body: "echo dummy")
    modelContext.insert(folder)
    modelContext.insert(snippet)
    snippet.folder = folder
    try modelContext.save()

    modelContext.delete(folder)
    try modelContext.save()

    #expect(try modelContext.fetchCount(FetchDescriptor<Folder>()) == 0)
    #expect(try modelContext.fetch(FetchDescriptor<Snippet>()).map(\.folder) == [nil])
  }

  @Test("タグを消してもスニペットは残る")
  func deletingTagKeepsSnippets() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let tag = SchemaV1.Tag(name: "dummy-tag")
    let snippet = Snippet(body: "echo dummy")
    modelContext.insert(tag)
    modelContext.insert(snippet)
    snippet.tags = [tag]
    try modelContext.save()

    modelContext.delete(tag)
    try modelContext.save()

    #expect(try modelContext.fetchCount(FetchDescriptor<SchemaV1.Tag>()) == 0)
    #expect(try modelContext.fetch(FetchDescriptor<Snippet>()).map { $0.tags ?? [] } == [[]])
  }

  @Test("スニペットグループを消すと項目も消え、スニペットは残る")
  func deletingSnippetGroupDeletesItems() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let snippetGroup = SnippetGroup(name: "dummy-group")
    let snippet = Snippet(body: "echo dummy")
    let snippetGroupItem = SnippetGroupItem(sortIndex: 0)
    modelContext.insert(snippetGroup)
    modelContext.insert(snippet)
    modelContext.insert(snippetGroupItem)
    snippetGroupItem.group = snippetGroup
    snippetGroupItem.snippet = snippet
    try modelContext.save()

    modelContext.delete(snippetGroup)
    try modelContext.save()

    #expect(try modelContext.fetchCount(FetchDescriptor<SnippetGroupItem>()) == 0)
    #expect(try modelContext.fetchCount(FetchDescriptor<Snippet>()) == 1)
  }

  @Test("スニペットを消すと、そのスニペットを指す項目も消え、グループは残る")
  func deletingSnippetDeletesItems() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let snippetGroup = SnippetGroup(name: "dummy-group")
    let snippet = Snippet(body: "echo dummy")
    let snippetGroupItem = SnippetGroupItem(sortIndex: 0)
    modelContext.insert(snippetGroup)
    modelContext.insert(snippet)
    modelContext.insert(snippetGroupItem)
    snippetGroupItem.group = snippetGroup
    snippetGroupItem.snippet = snippet
    try modelContext.save()

    modelContext.delete(snippet)
    try modelContext.save()

    #expect(try modelContext.fetchCount(FetchDescriptor<SnippetGroupItem>()) == 0)
    #expect(try modelContext.fetch(FetchDescriptor<SnippetGroup>()).map { $0.items ?? [] } == [[]])
  }

  @Test("端末内のストアのモデルを保存して読み出せる")
  func saveAndFetchLocalModels() throws {
    let container = try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none)
    let writingContext = ModelContext(container)
    let snippetID = UUID()
    writingContext.insert(SnippetEmbedding(snippetID: snippetID, modelIdentifier: "dummy-model", sourceHash: "dummy-hash", vector: Data([1, 2, 3, 4])))
    writingContext.insert(MCPClient(id: UUID(), name: "dummy-client", createdAt: Date(timeIntervalSince1970: 0)))
    try writingContext.save()

    let readingContext = ModelContext(container)
    #expect(try readingContext.fetch(FetchDescriptor<SnippetEmbedding>()).map(\.snippetID) == [snippetID])
    #expect(try readingContext.fetch(FetchDescriptor<MCPClient>()).map(\.name) == ["dummy-client"])
  }
}
