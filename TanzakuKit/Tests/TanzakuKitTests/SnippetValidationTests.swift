import Foundation
import SwiftData
import Testing

@testable import TanzakuKit

/// 保存前の検査 (空の本文・キーワードの一意) を確かめる。
struct SnippetValidationTests {
  @Test("本文が空か空白と改行だけならエラーにする", arguments: ["", " ", "\n\t "])
  func emptyBodyIsRejected(body: String) {
    #expect(throws: SnippetValidationError.emptyBody) {
      try validateSnippetBody(body: body)
    }
  }

  @Test("本文に文字があれば通す")
  func nonEmptyBodyIsAccepted() throws {
    try validateSnippetBody(body: " echo dummy ")
  }

  @Test("別のスニペットと同じキーワードはエラーにする")
  func keywordUsedByAnotherSnippetIsRejected() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let existingSnippet = Snippet(body: "echo dummy")
    existingSnippet.keyword = ";dummy"
    modelContext.insert(existingSnippet)
    try modelContext.save()

    #expect(throws: SnippetValidationError.keywordAlreadyUsed(keyword: ";dummy")) {
      try validateKeywordIsUnique(keyword: ";dummy", ownerID: UUID(), modelContext: modelContext)
    }
  }

  @Test("スニペットグループと同じキーワードはエラーにする")
  func keywordUsedBySnippetGroupIsRejected() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let snippetGroup = SnippetGroup(name: "dummy-group")
    snippetGroup.keyword = ";dummy"
    modelContext.insert(snippetGroup)
    try modelContext.save()

    #expect(throws: SnippetValidationError.keywordAlreadyUsed(keyword: ";dummy")) {
      try validateKeywordIsUnique(keyword: ";dummy", ownerID: UUID(), modelContext: modelContext)
    }
  }

  @Test("保存しようとしているもの自身のキーワードは重複に数えない")
  func ownKeywordIsAccepted() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let snippet = Snippet(body: "echo dummy")
    snippet.keyword = ";dummy"
    modelContext.insert(snippet)
    try modelContext.save()

    try validateKeywordIsUnique(keyword: ";dummy", ownerID: snippet.id, modelContext: modelContext)
  }

  @Test("大文字と小文字が違うキーワード・キーワードなしは通す", arguments: [";DUMMY", "", nil] as [String?])
  func differentOrEmptyKeywordIsAccepted(keyword: String?) throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let snippet = Snippet(body: "echo dummy")
    snippet.keyword = ";dummy"
    modelContext.insert(snippet)
    let snippetWithoutKeyword = Snippet(body: "echo dummy")
    snippetWithoutKeyword.keyword = ""
    modelContext.insert(snippetWithoutKeyword)
    try modelContext.save()

    try validateKeywordIsUnique(keyword: keyword, ownerID: UUID(), modelContext: modelContext)
  }
}
