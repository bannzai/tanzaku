import Foundation
import SwiftData
import Testing

@testable import TanzakuKit

/// 添付 (本文の代わりの画像・動画) のファイル名・行の書き出し・ファイルの読み込み・キーボードに並べるスニペットを確かめる。
struct SnippetAttachmentTests {
  @Test("選んだファイルの名前があれば、前後の空白を除いてそのまま使う")
  func originalFileNameIsKept() {
    #expect(snippetAttachmentFileName(originalFileName: " dummy-screenshot.png ", contentType: "public.png") == "dummy-screenshot.png")
  }

  @Test(
    "ファイルの名前が無い・空白だけの時は、種類から名前を作る",
    arguments: [
      (nil, "public.png", "image.png"),
      ("  ", "public.jpeg", "image.jpeg"),
      (nil, "com.apple.quicktime-movie", "video.mov"),
    ] as [(String?, String, String)]
  )
  func fileNameIsMadeFromContentType(originalFileName: String?, contentType: String, expectedFileName: String) {
    #expect(snippetAttachmentFileName(originalFileName: originalFileName, contentType: contentType) == expectedFileName)
  }

  @Test("行の 2 行目は、本文のスニペットでは本文の 1 行目、添付のスニペットでは添付の種類の名前")
  func contentSummaryUsesAttachmentKind() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let textSnippet = Snippet(body: "\necho dummy\nsecond")
    let imageSnippet = Snippet(body: "")
    imageSnippet.attachmentContentType = "public.png"
    let videoSnippet = Snippet(body: "")
    videoSnippet.attachmentContentType = "com.apple.quicktime-movie"
    modelContext.insert(textSnippet)
    modelContext.insert(imageSnippet)
    modelContext.insert(videoSnippet)

    #expect(snippetContentSummary(snippet: textSnippet) == "echo dummy")
    #expect(snippetContentSummary(snippet: imageSnippet) == snippetAttachmentKindLabel(contentType: "public.png"))
    #expect(snippetContentSummary(snippet: videoSnippet) == snippetAttachmentKindLabel(contentType: "com.apple.quicktime-movie"))
    #expect(snippetAttachmentKindLabel(contentType: "public.png") != snippetAttachmentKindLabel(contentType: "com.apple.quicktime-movie"))
  }

  @Test("選んだ画像のファイルを、データ・種類・ファイル名として読む")
  func readsImageFile() throws {
    let directoryURL = try makeTemporaryDirectory()
    defer {
      try? FileManager.default.removeItem(at: directoryURL)
    }
    let fileURL = directoryURL.appending(path: "dummy-screenshot.png")
    let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    try pngData.write(to: fileURL)

    let attachmentFile = try readSnippetAttachmentFile(fileURL: fileURL)

    #expect(attachmentFile.attachmentData == pngData)
    #expect(attachmentFile.attachmentContentType == "public.png")
    #expect(attachmentFile.attachmentFileName == "dummy-screenshot.png")
  }

  @Test("画像でも動画でもないファイルは読まずに unsupportedAttachmentType を投げる")
  func rejectsNonMediaFile() throws {
    let directoryURL = try makeTemporaryDirectory()
    defer {
      try? FileManager.default.removeItem(at: directoryURL)
    }
    let fileURL = directoryURL.appending(path: "dummy.txt")
    try Data("dummy".utf8).write(to: fileURL)

    #expect(throws: SnippetValidationError.unsupportedAttachmentType(contentType: "public.plain-text")) {
      try readSnippetAttachmentFile(fileURL: fileURL)
    }
  }

  @Test("キーボードに並べてよいのは添付の無い本文のスニペットだけ")
  func keyboardTextSnippetsExcludeAttachments() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let textSnippet = Snippet(body: "echo dummy")
    let attachmentSnippet = Snippet(body: "")
    attachmentSnippet.attachmentData = Data([0x00])
    attachmentSnippet.attachmentContentType = "public.png"
    attachmentSnippet.attachmentFileName = "dummy.png"
    modelContext.insert(textSnippet)
    modelContext.insert(attachmentSnippet)
    try modelContext.save()

    #expect(try keyboardTextSnippetModelIDs(modelContext: modelContext) == [textSnippet.persistentModelID])
  }

  /// テストのファイルを置く、テストごとの一時フォルダを作る。
  private func makeTemporaryDirectory() throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory.appending(path: "SnippetAttachmentTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL
  }
}
