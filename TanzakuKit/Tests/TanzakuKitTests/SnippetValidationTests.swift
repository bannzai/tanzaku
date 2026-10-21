import Foundation
import SwiftData
import Testing

@testable import TanzakuKit

/// 保存前の検査 (空の本文・キーワードの書式・キーワードの一意) を確かめる。
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

  @Test("本文も添付も無ければ emptyBody にする")
  func emptyBodyWithoutAttachmentIsRejected() {
    #expect(throws: SnippetValidationError.emptyBody) {
      try validateSnippetContent(body: " \n", attachmentData: nil, attachmentContentType: nil)
    }
  }

  @Test("添付 (画像・動画) があれば本文が空でも通す", arguments: ["public.png", "public.jpeg", "com.apple.quicktime-movie", "public.mpeg-4"])
  func attachmentWithEmptyBodyIsAccepted(contentType: String) throws {
    try validateSnippetContent(body: "", attachmentData: Data([0x00, 0x01]), attachmentContentType: contentType)
  }

  @Test("添付が上限より大きければ attachmentTooLarge にし、上限ちょうどは通す")
  func attachmentLargerThanLimitIsRejected() throws {
    try validateSnippetContent(body: "", attachmentData: Data(count: snippetAttachmentMaximumByteCount), attachmentContentType: "public.png")
    #expect(throws: SnippetValidationError.attachmentTooLarge(maximumByteCount: snippetAttachmentMaximumByteCount)) {
      try validateSnippetContent(body: "", attachmentData: Data(count: snippetAttachmentMaximumByteCount + 1), attachmentContentType: "public.png")
    }
  }

  @Test("画像でも動画でもない添付は unsupportedAttachmentType にする", arguments: ["public.plain-text", "com.adobe.pdf", "dummy.unknown-type"])
  func unsupportedAttachmentTypeIsRejected(contentType: String) {
    #expect(throws: SnippetValidationError.unsupportedAttachmentType(contentType: contentType)) {
      try validateSnippetContent(body: "", attachmentData: Data([0x00]), attachmentContentType: contentType)
    }
  }

  @Test("空白と改行だけのキーワードは blankKeyword にする", arguments: [" ", "  ", "\t", " \n"])
  func blankKeywordIsRejected(keyword: String) {
    #expect(throws: SnippetValidationError.blankKeyword) {
      try validateKeywordFormat(keyword: keyword)
    }
  }

  @Test("1 文字のキーワードは keywordTooShort にする", arguments: [";", "a", "あ"])
  func oneCharacterKeywordIsRejected(keyword: String) {
    #expect(throws: SnippetValidationError.keywordTooShort(minimumLength: 2)) {
      try validateKeywordFormat(keyword: keyword)
    }
  }

  @Test("2 文字以上のキーワード・キーワードなしは書式の検査を通す", arguments: [";a", "ab", " ;", ";tkw", "", nil] as [String?])
  func keywordWithEnoughCharactersIsAccepted(keyword: String?) throws {
    try validateKeywordFormat(keyword: keyword)
  }

  @Test("編集画面とスニペットグループの保存でも、1 文字と空白だけのキーワードを保存させない")
  func editsRejectInvalidKeywordFormat() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    #expect(throws: SnippetValidationError.keywordTooShort(minimumLength: 2)) {
      try applySnippetEdit(
        snippet: Snippet(body: ""),
        body: "echo dummy",
        attachmentData: nil,
        attachmentContentType: nil,
        attachmentFileName: nil,
        title: "",
        keyword: ";",
        language: nil,
        color: nil,
        folder: nil,
        tagNames: [],
        modelContext: modelContext,
        now: .now
      )
    }
    #expect(throws: SnippetValidationError.blankKeyword) {
      try applySnippetGroupEdit(snippetGroup: SnippetGroup(name: ""), name: "dummy-group", keyword: "  ", snippets: [], modelContext: modelContext, now: .now)
    }
    #expect(try modelContext.fetchCount(FetchDescriptor<Snippet>()) == 0)
    #expect(try modelContext.fetchCount(FetchDescriptor<SnippetGroup>()) == 0)
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
