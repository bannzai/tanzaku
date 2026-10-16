import Foundation
import SwiftData
import TanzakuKit
import Testing

@testable import Tanzaku

/// キーワード展開の許可のウィンドウを、許可が無くキーワードを持つスニペットかスニペットグループがある時だけ出すことを確かめる。
struct SnippetGroupKeywordPermissionTests {
  /// テストごとに空のストアを使い、ほかのテストのスニペットに触れないようにする。
  let modelContext: ModelContext

  init() throws {
    // テストごとに別の in-memory のストアを開くため。
    modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
  }

  @Test("許可が無く、キーワードを持つスニペットがあれば出す")
  func snippetWithKeyword() throws {
    let snippet = Snippet(body: "dummy-body-for-test")
    snippet.keyword = "dummykey"
    modelContext.insert(snippet)
    try modelContext.save()

    #expect(try isKeywordPermissionWindowNeeded(isKeywordExpansionAllowed: false, modelContext: modelContext))
  }

  @Test("許可が無く、キーワードを持つスニペットグループがあれば出す")
  func snippetGroupWithKeyword() throws {
    let snippetGroup = SnippetGroup(name: "dummy-group")
    snippetGroup.keyword = ";dummy"
    modelContext.insert(snippetGroup)
    try modelContext.save()

    #expect(try isKeywordPermissionWindowNeeded(isKeywordExpansionAllowed: false, modelContext: modelContext))
  }

  @Test("キーワードを持つスニペットもスニペットグループも無ければ、許可が無くても出さない")
  func noKeyword() throws {
    modelContext.insert(Snippet(body: "dummy-body-for-test"))
    modelContext.insert(SnippetGroup(name: "dummy-group"))
    try modelContext.save()

    #expect(try !isKeywordPermissionWindowNeeded(isKeywordExpansionAllowed: false, modelContext: modelContext))
  }

  @Test("許可がすべてあれば、キーワードがあっても出さない")
  func allowed() throws {
    let snippet = Snippet(body: "dummy-body-for-test")
    snippet.keyword = "dummykey"
    modelContext.insert(snippet)
    try modelContext.save()

    #expect(try !isKeywordPermissionWindowNeeded(isKeywordExpansionAllowed: true, modelContext: modelContext))
  }
}
