import Foundation
import SwiftData
import Testing

@testable import TanzakuKit

/// スニペットグループの項目の並べ替えと保存 (`replaceSnippetGroupItems`・`saveEditedSnippetGroup`) を確かめる。
struct SnippetGroupEditingTests {
  /// 本文だけを持つスニペットを `modelContext` に入れる。
  private func insertSnippets(bodies: [String], modelContext: ModelContext) -> [Snippet] {
    bodies.map { body in
      let snippet = Snippet(body: body)
      modelContext.insert(snippet)
      return snippet
    }
  }

  @Test("項目を渡した並びに置き換え、残る項目は作り直さず、外した項目は消す")
  func replaceKeepsRemainingItems() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let snippets = insertSnippets(bodies: ["deploy", "release", "run-test"], modelContext: modelContext)
    let snippetGroup = SnippetGroup(name: "dummy-group")
    modelContext.insert(snippetGroup)
    replaceSnippetGroupItems(snippetGroup: snippetGroup, snippets: snippets, modelContext: modelContext)
    try modelContext.save()
    let releaseItemID = try #require(snippetGroup.items?.first { $0.snippet?.body == "release" }?.id)

    replaceSnippetGroupItems(snippetGroup: snippetGroup, snippets: [snippets[2], snippets[1]], modelContext: modelContext)
    try modelContext.save()

    #expect(snippetGroupSnippets(snippetGroup: snippetGroup).map(\.body) == ["run-test", "release"])
    #expect(snippetGroup.items?.first { $0.snippet?.body == "release" }?.id == releaseItemID)
    #expect(try modelContext.fetchCount(FetchDescriptor<SnippetGroupItem>()) == 2)
    #expect(try modelContext.fetchCount(FetchDescriptor<Snippet>()) == 3)
  }

  @Test("同じスニペットが 2 回あれば最初の位置だけを使い、同じ並びで何度呼んでも項目は増えない")
  func replaceIsIdempotent() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let snippets = insertSnippets(bodies: ["deploy", "release"], modelContext: modelContext)
    let snippetGroup = SnippetGroup(name: "dummy-group")
    modelContext.insert(snippetGroup)

    for _ in 0..<2 {
      replaceSnippetGroupItems(snippetGroup: snippetGroup, snippets: [snippets[1], snippets[0], snippets[1]], modelContext: modelContext)
      try modelContext.save()
    }

    #expect(snippetGroupSnippets(snippetGroup: snippetGroup).map(\.body) == ["release", "deploy"])
    #expect(try modelContext.fetchCount(FetchDescriptor<SnippetGroupItem>()) == 2)
  }

  @Test("保存の前に外した項目を足し直すと、足し直したスニペットは保存の後も残る")
  func readdedItemBeforeSaveIsKept() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let snippets = insertSnippets(bodies: ["deploy", "release"], modelContext: modelContext)
    let snippetGroup = SnippetGroup(name: "dummy-group")
    modelContext.insert(snippetGroup)
    replaceSnippetGroupItems(snippetGroup: snippetGroup, snippets: snippets, modelContext: modelContext)
    try modelContext.save()

    replaceSnippetGroupItems(snippetGroup: snippetGroup, snippets: [snippets[0]], modelContext: modelContext)
    replaceSnippetGroupItems(snippetGroup: snippetGroup, snippets: snippets, modelContext: modelContext)
    try modelContext.save()

    #expect(snippetGroupSnippets(snippetGroup: snippetGroup).map(\.body) == ["deploy", "release"])
    #expect(try modelContext.fetchCount(FetchDescriptor<SnippetGroupItem>()) == 2)
  }

  @Test("名前の前後の空白を除き、空欄のキーワードは無しにして保存する")
  func savesNormalizedSnippetGroup() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let snippetGroup = SnippetGroup(name: " focus-app ")
    snippetGroup.keyword = ""
    modelContext.insert(snippetGroup)
    let now = Date(timeIntervalSince1970: 1_000)

    try saveEditedSnippetGroup(snippetGroup: snippetGroup, modelContext: modelContext, now: now)

    #expect(snippetGroup.name == "focus-app")
    #expect(snippetGroup.keyword == nil)
    #expect(snippetGroup.updatedAt == now)
    #expect(!modelContext.hasChanges)
  }

  @Test("名前が空か、スニペットと同じキーワードなら保存しない")
  func invalidSnippetGroupIsNotSaved() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let snippet = Snippet(body: "echo dummy")
    snippet.keyword = ";dummy"
    modelContext.insert(snippet)
    try modelContext.save()
    let unnamedSnippetGroup = SnippetGroup(name: " ")
    modelContext.insert(unnamedSnippetGroup)

    #expect(throws: SnippetValidationError.emptySnippetGroupName) {
      try saveEditedSnippetGroup(snippetGroup: unnamedSnippetGroup, modelContext: modelContext, now: .now)
    }

    unnamedSnippetGroup.name = "dummy-group"
    unnamedSnippetGroup.keyword = ";dummy"
    #expect(throws: SnippetValidationError.keywordAlreadyUsed(keyword: ";dummy")) {
      try saveEditedSnippetGroup(snippetGroup: unnamedSnippetGroup, modelContext: modelContext, now: .now)
    }
  }
}
