import Foundation
import SwiftData
import Testing

@testable import TanzakuKit

/// `applySnippetEdit` の保存前の検査と、スニペットへの書き込みを確かめる。
struct SnippetEditTests {
  @Test("本文が空の新規スニペットはエラーにし、ストアに入れない")
  func emptyBodyIsRejectedWithoutInsert() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let snippet = Snippet(body: "")

    #expect(throws: SnippetValidationError.emptyBody) {
      try applySnippetEdit(
        snippet: snippet, body: " \n", title: "dummy", keyword: "", language: nil, color: nil, folder: nil, tagNames: ["dummy-tag"],
        modelContext: modelContext, now: .now
      )
    }
    #expect(snippet.modelContext == nil)
    #expect(try modelContext.fetchCount(FetchDescriptor<Snippet>()) == 0)
    #expect(try modelContext.fetchCount(FetchDescriptor<Tag>()) == 0)
  }

  @Test("別のスニペットかスニペットグループと同じキーワードはエラーにし、既存のスニペットを書き換えない")
  func duplicateKeywordIsRejectedWithoutChange() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let otherSnippet = Snippet(body: "echo other")
    otherSnippet.keyword = ";snippet"
    modelContext.insert(otherSnippet)
    let snippetGroup = SnippetGroup(name: "dummy-group")
    snippetGroup.keyword = ";group"
    modelContext.insert(snippetGroup)
    let snippet = Snippet(body: "echo before")
    modelContext.insert(snippet)
    try modelContext.save()

    for keyword in [";snippet", ";group"] {
      #expect(throws: SnippetValidationError.keywordAlreadyUsed(keyword: keyword)) {
        try applySnippetEdit(
          snippet: snippet, body: "echo after", title: "", keyword: keyword, language: nil, color: nil, folder: nil, tagNames: [],
          modelContext: modelContext, now: .now
        )
      }
    }
    #expect(snippet.body == "echo before")
    #expect(snippet.keyword == nil)
  }

  @Test("新規スニペットは検査を通るとストアに入り、入力した値と作成・更新の日時と主体を持つ")
  func newSnippetIsInsertedWithValues() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let folder = Folder(name: "dummy-folder")
    modelContext.insert(folder)
    let now = Date(timeIntervalSince1970: 1000)
    let snippet = Snippet(body: "")

    try applySnippetEdit(
      snippet: snippet, body: "echo dummy-token-for-test", title: "Dummy title", keyword: ";dummy", language: .shell, color: .ai,
      folder: folder, tagNames: [], modelContext: modelContext, now: now
    )

    #expect(snippet.modelContext != nil)
    #expect(snippet.body == "echo dummy-token-for-test")
    #expect(snippet.title == "Dummy title")
    #expect(snippet.keyword == ";dummy")
    #expect(snippet.language == "shell")
    #expect(snippet.colorRawValue == "ai")
    #expect(snippet.folder?.id == folder.id)
    #expect(snippet.createdAt == now)
    #expect(snippet.updatedAt == now)
    #expect(snippet.updatedByKind == "user")
  }

  @Test("空白だけのタイトルと空のキーワードは「なし」にする")
  func emptyTitleAndKeywordBecomeNil() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let snippet = Snippet(body: "echo dummy")
    snippet.title = "before"
    snippet.keyword = ";before"
    modelContext.insert(snippet)

    try applySnippetEdit(
      snippet: snippet, body: "echo dummy", title: "  ", keyword: "", language: nil, color: nil, folder: nil, tagNames: [],
      modelContext: modelContext, now: .now
    )

    #expect(snippet.title == nil)
    #expect(snippet.keyword == nil)
    #expect(snippet.language == nil)
    #expect(snippet.colorRawValue == nil)
  }

  @Test("既存のスニペットの更新は作成日時を変えず、AI エージェントが更新した記録をユーザーに戻す")
  func existingSnippetUpdateKeepsCreatedAtAndResetsUpdater() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let createdAt = Date(timeIntervalSince1970: 0)
    let snippet = Snippet(body: "echo dummy")
    snippet.createdAt = createdAt
    snippet.createdByKind = "mcp"
    snippet.createdByClientName = "Dummy Client"
    snippet.updatedByKind = "mcp"
    snippet.updatedByClientName = "Dummy Client"
    modelContext.insert(snippet)
    let now = Date(timeIntervalSince1970: 1000)

    try applySnippetEdit(
      snippet: snippet, body: "echo edited", title: "", keyword: "", language: nil, color: nil, folder: nil, tagNames: [],
      modelContext: modelContext, now: now
    )

    #expect(snippet.createdAt == createdAt)
    #expect(snippet.createdByKind == "mcp")
    #expect(snippet.createdByClientName == "Dummy Client")
    #expect(snippet.updatedAt == now)
    #expect(snippet.updatedByKind == "user")
    #expect(snippet.updatedByClientName == nil)
  }

  @Test("タグは同じ名前の既存のタグを使い、無い名前だけ作る。空の名前と重複した名前は除く")
  func tagNamesAreResolved() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let existingTag = Tag(name: "shell")
    modelContext.insert(existingTag)
    let snippet = Snippet(body: "")

    try applySnippetEdit(
      snippet: snippet, body: "echo dummy", title: "", keyword: "", language: nil, color: nil, folder: nil,
      tagNames: ["shell", " ci ", "", "ci", "Shell"], modelContext: modelContext, now: .now
    )

    #expect(snippet.tags?.map(\.name).sorted() == ["Shell", "ci", "shell"])
    #expect(snippet.tags?.contains { $0.id == existingTag.id } == true)
    #expect(try modelContext.fetchCount(FetchDescriptor<Tag>()) == 3)
  }
}
