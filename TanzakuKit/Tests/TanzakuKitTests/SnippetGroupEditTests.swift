import Foundation
import SwiftData
import Testing

@testable import TanzakuKit

/// `applySnippetGroupEdit` の保存前の検査と、項目の並び替え・追加・削除を確かめる。
struct SnippetGroupEditTests {
  /// 本文だけを持つスニペットをストアに入れる。
  private func insertSnippet(modelContext: ModelContext, body: String) -> Snippet {
    let snippet = Snippet(body: body)
    modelContext.insert(snippet)
    return snippet
  }

  @Test("スニペットと同じキーワードの新規グループはエラーにし、ストアに入れない")
  func duplicateKeywordIsRejectedWithoutInsert() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let snippet = insertSnippet(modelContext: modelContext, body: "echo dummy")
    snippet.keyword = ";dummy"
    try modelContext.save()
    let snippetGroup = SnippetGroup(name: "")

    #expect(throws: SnippetValidationError.keywordAlreadyUsed(keyword: ";dummy")) {
      try applySnippetGroupEdit(
        snippetGroup: snippetGroup, name: "dummy-group", keyword: ";dummy", snippets: [snippet], modelContext: modelContext, now: .now
      )
    }
    #expect(snippetGroup.modelContext == nil)
    #expect(try modelContext.fetchCount(FetchDescriptor<SnippetGroup>()) == 0)
    #expect(try modelContext.fetchCount(FetchDescriptor<SnippetGroupItem>()) == 0)
  }

  @Test("新規グループは検査を通るとストアに入り、渡した順に項目を並べ、同じスニペットは 1 つにする")
  func newGroupIsInsertedWithOrderedItems() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let deploySnippet = insertSnippet(modelContext: modelContext, body: "make deploy")
    let releaseSnippet = insertSnippet(modelContext: modelContext, body: "make release")
    let now = Date(timeIntervalSince1970: 1000)
    let snippetGroup = SnippetGroup(name: "")

    try applySnippetGroupEdit(
      snippetGroup: snippetGroup, name: "dummy-group", keyword: ";dummy", snippets: [releaseSnippet, deploySnippet, releaseSnippet],
      modelContext: modelContext, now: now
    )

    #expect(snippetGroup.modelContext != nil)
    #expect(snippetGroup.name == "dummy-group")
    #expect(snippetGroup.keyword == ";dummy")
    #expect(snippetGroup.createdAt == now)
    #expect(sortedSnippetGroupItems(snippetGroup: snippetGroup).compactMap(\.snippet?.id) == [releaseSnippet.id, deploySnippet.id])
    #expect(sortedSnippetGroupItems(snippetGroup: snippetGroup).map(\.sortIndex) == [0, 1])
  }

  @Test("既存のグループは項目を使い回して並べ替え、外したスニペットの項目だけを消す")
  func existingGroupReordersAndRemovesItems() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let deploySnippet = insertSnippet(modelContext: modelContext, body: "make deploy")
    let releaseSnippet = insertSnippet(modelContext: modelContext, body: "make release")
    let testSnippet = insertSnippet(modelContext: modelContext, body: "make test")
    let snippetGroup = SnippetGroup(name: "")
    try applySnippetGroupEdit(
      snippetGroup: snippetGroup, name: "dummy-group", keyword: "", snippets: [deploySnippet, releaseSnippet, testSnippet],
      modelContext: modelContext, now: .now
    )
    try modelContext.save()
    let releaseItemID = try #require(sortedSnippetGroupItems(snippetGroup: snippetGroup).first { $0.snippet?.id == releaseSnippet.id }?.id)

    try applySnippetGroupEdit(
      snippetGroup: snippetGroup, name: "dummy-group", keyword: "", snippets: [testSnippet, releaseSnippet],
      modelContext: modelContext, now: .now
    )
    try modelContext.save()

    #expect(sortedSnippetGroupItems(snippetGroup: snippetGroup).compactMap(\.snippet?.id) == [testSnippet.id, releaseSnippet.id])
    #expect(sortedSnippetGroupItems(snippetGroup: snippetGroup).last?.id == releaseItemID)
    #expect(try modelContext.fetchCount(FetchDescriptor<SnippetGroupItem>()) == 2)
    #expect(try modelContext.fetchCount(FetchDescriptor<Snippet>()) == 3)
  }

  @Test("空のキーワードは「なし」にする")
  func emptyKeywordBecomesNil() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let snippetGroup = SnippetGroup(name: "dummy-group")
    snippetGroup.keyword = ";before"
    modelContext.insert(snippetGroup)

    try applySnippetGroupEdit(snippetGroup: snippetGroup, name: "dummy-group", keyword: "", snippets: [], modelContext: modelContext, now: .now)

    #expect(snippetGroup.keyword == nil)
  }
}
