#if DEBUG
  import Foundation
  import SwiftData
  import TanzakuKit
  import Testing

  @testable import Tanzaku

  /// 開発者メニューの「Delete All Snippets」が、リレーションを持つスニペットを消しても失敗しないことを確かめる。
  struct DeveloperCommandsTests {
    @Test("フォルダ・タグ・スニペットグループの項目・意味検索のベクトルを持つスニペットをすべて消し、何度呼んでも失敗しない")
    func deleteAllSnippetDataDeletesSnippetsWithRelationships() throws {
      let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
      let snippet = Snippet(body: "export API_TOKEN=dummy-token-for-test")
      modelContext.insert(snippet)
      snippet.folder = Folder(name: "dummy folder")
      snippet.tags = [TanzakuKit.Tag(name: "shell"), TanzakuKit.Tag(name: "auth")]
      let snippetGroup = SnippetGroup(name: "dummy group")
      modelContext.insert(snippetGroup)
      let snippetGroupItem = SnippetGroupItem(sortIndex: 0)
      modelContext.insert(snippetGroupItem)
      snippetGroupItem.group = snippetGroup
      snippetGroupItem.snippet = snippet
      modelContext.insert(SnippetEmbedding(snippetID: snippet.id, modelIdentifier: "dummy-model", sourceHash: "dummy-hash", vector: Data()))
      try modelContext.save()

      try deleteAllSnippetData(modelContext: modelContext)
      try deleteAllSnippetData(modelContext: modelContext)

      #expect(try modelContext.fetchCount(FetchDescriptor<Snippet>()) == 0)
      #expect(try modelContext.fetchCount(FetchDescriptor<Folder>()) == 0)
      #expect(try modelContext.fetchCount(FetchDescriptor<TanzakuKit.Tag>()) == 0)
      #expect(try modelContext.fetchCount(FetchDescriptor<SnippetGroupItem>()) == 0)
      #expect(try modelContext.fetchCount(FetchDescriptor<SnippetEmbedding>()) == 0)
      #expect(try modelContext.fetchCount(FetchDescriptor<SnippetGroup>()) == 1)
    }
  }
#endif
