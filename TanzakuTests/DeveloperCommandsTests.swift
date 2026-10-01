#if DEBUG
  import Foundation
  import SwiftData
  import TanzakuKit
  import Testing

  @testable import Tanzaku

  /// 開発者メニューの見本の投入が冪等で、「Delete Sample Data」が見本だけを消し、「Delete All Snippets」がリレーションを持つスニペットを消しても失敗しないことを確かめる。
  struct DeveloperCommandsTests {
    @Test("見本の投入を 2 回実行しても、スニペット・フォルダ・タグ・スニペットグループの件数が 1 回目と同じ")
    func insertingSampleDataTwiceKeepsCounts() throws {
      let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
      let insertAllSampleData = {
        try insertLauncherSampleData(modelContext: modelContext, now: .now)
        try insertManagerSampleData(modelContext: modelContext, now: .now)
        _ = try insertDeletionRequestSampleSnippet(modelContext: modelContext, now: .now)
        try modelContext.save()
      }
      let counts = {
        [
          try modelContext.fetchCount(FetchDescriptor<Snippet>()),
          try modelContext.fetchCount(FetchDescriptor<Folder>()),
          try modelContext.fetchCount(FetchDescriptor<TanzakuKit.Tag>()),
          try modelContext.fetchCount(FetchDescriptor<SnippetGroup>()),
        ]
      }

      try insertAllSampleData()
      let countsAfterFirstInsertion = try counts()
      try insertAllSampleData()

      #expect(try counts() == countsAfterFirstInsertion)
      let folderNames = try modelContext.fetch(FetchDescriptor<Folder>()).map(\.name)
      #expect(folderNames.count == Set(folderNames).count)
      let tagNames = try modelContext.fetch(FetchDescriptor<TanzakuKit.Tag>()).map(\.name)
      #expect(tagNames.count == Set(tagNames).count)
    }

    @Test("見本のキーワードをスニペットグループが使っていれば、その見本だけを飛ばして他の見本を入れる")
    func insertingSampleDataSkipsKeywordsUsedBySnippetGroups() throws {
      let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
      for keyword in ["envkey", "envrc"] {
        let snippetGroup = SnippetGroup(name: "dummy user group \(keyword)")
        modelContext.insert(snippetGroup)
        snippetGroup.keyword = keyword
      }
      try modelContext.save()

      try insertLauncherSampleData(modelContext: modelContext, now: .now)
      let deletionRequestSnippet = try insertDeletionRequestSampleSnippet(modelContext: modelContext, now: .now)
      try modelContext.save()

      #expect(Set(try modelContext.fetch(FetchDescriptor<Snippet>()).compactMap(\.keyword)) == ["ghsec"])
      #expect(deletionRequestSnippet.keyword == nil)
    }

    @Test("見本の操作が途中で失敗したら、保存していない変更を捨てて後の保存に残さない")
    func saveDeveloperSampleDataChangesRollsBackOnFailure() throws {
      let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))

      #expect(throws: SnippetValidationError.emptyBody) {
        try saveDeveloperSampleDataChanges(modelContext: modelContext) {
          modelContext.insert(Folder(name: "開発環境"))
          throw SnippetValidationError.emptyBody
        }
      }
      try modelContext.save()

      #expect(try modelContext.fetchCount(FetchDescriptor<Folder>()) == 0)
    }

    @Test("「Delete Sample Data」は見本と見本だけが入った重複のフォルダ・タグを消し、ユーザーのスニペット・フォルダ・タグ・スニペットグループを残す")
    func deleteDeveloperSampleDataKeepsUserData() throws {
      let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
      let userSnippet = Snippet(body: "echo dummy-user-snippet")
      modelContext.insert(userSnippet)
      userSnippet.folder = Folder(name: "dummy user folder")
      userSnippet.tags = [TanzakuKit.Tag(name: "dummy-user-tag")]
      // 見本と同じ名前のフォルダ・タグに入れたユーザーのスニペット。フォルダ・タグごと残す。
      let userSnippetInSampleFolder = Snippet(body: "echo dummy-user-snippet-in-sample-folder")
      modelContext.insert(userSnippetInSampleFolder)
      userSnippetInSampleFolder.folder = Folder(name: "開発環境")
      userSnippetInSampleFolder.tags = [TanzakuKit.Tag(name: "shell")]
      let userSnippetGroup = SnippetGroup(name: "dummy user group")
      modelContext.insert(userSnippetGroup)
      userSnippetGroup.keyword = ";dummy-user"
      // 投入が冪等になる前の見本が残した、スニペットの無い重複のフォルダ・タグ。
      for _ in 0..<3 {
        modelContext.insert(Folder(name: "開発環境"))
        modelContext.insert(TanzakuKit.Tag(name: "direnv"))
      }
      try modelContext.save()
      try insertLauncherSampleData(modelContext: modelContext, now: .now)
      try insertManagerSampleData(modelContext: modelContext, now: .now)
      _ = try insertDeletionRequestSampleSnippet(modelContext: modelContext, now: .now)
      try modelContext.save()

      try deleteDeveloperSampleData(modelContext: modelContext)
      try deleteDeveloperSampleData(modelContext: modelContext)

      #expect(Set(try modelContext.fetch(FetchDescriptor<Snippet>()).map(\.body)) == ["echo dummy-user-snippet", "echo dummy-user-snippet-in-sample-folder"])
      #expect(try modelContext.fetch(FetchDescriptor<Folder>()).map(\.name).sorted() == ["dummy user folder", "開発環境"])
      #expect(try modelContext.fetch(FetchDescriptor<TanzakuKit.Tag>()).map(\.name).sorted() == ["dummy-user-tag", "shell"])
      #expect(try modelContext.fetch(FetchDescriptor<SnippetGroup>()).map(\.name) == ["dummy user group"])
      #expect(userSnippetInSampleFolder.folder?.name == "開発環境")
    }

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
