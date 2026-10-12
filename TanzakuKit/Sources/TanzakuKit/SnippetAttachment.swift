import Foundation
import SwiftData
import UniformTypeIdentifiers

/// 添付 (本文の代わりに出力する画像・動画) のデータの大きさの上限のバイト数。
///
/// CloudKit の Asset の項目の最大のファイルサイズ 50 MB (CloudKit Web Services Reference「Data Size Limits」 https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/PropertyMetrics.html )。
/// 同期 (#19) では 1 MB を超える値を Core Data が Asset に変えて送る (`documents/data-model.md`「Snippet」) ため、Apple が Asset の大きさを数値で示している唯一の上限に合わせる。MB を 1000 × 1000 バイトと読む方が上限に収まる側のため、10 進で数える。
public let snippetAttachmentMaximumByteCount = 50_000_000

/// スニペットに添付として入れられる種類。画像と動画だけ。
public let snippetAttachmentAllowedContentTypes: [UTType] = [.image, .movie]

/// スニペットが添付 (画像・動画) を持つか。
///
/// 添付のデータ (`attachmentData`) ではなく種類 (`attachmentContentType`) で判定する。データはストアの外のファイルにあり、読むと添付の全体をメモリに載せるため。
public func snippetHasAttachment(snippet: Snippet) -> Bool {
  snippet.attachmentContentType != nil
}

/// 添付の種類が画像か。`false` は動画 (保存前の検査で画像と動画以外は断る)。
public func isSnippetAttachmentImage(contentType: String) -> Bool {
  UTType(contentType)?.conforms(to: .image) ?? false
}

/// 添付の種類の名前 (「画像」・「動画」)。一覧・ランチャーの行の 2 行目に、本文の 1 行目の代わりに出す。
public func snippetAttachmentKindLabel(contentType: String) -> String {
  isSnippetAttachmentImage(contentType: contentType)
    ? String(localized: "Image", bundle: .module)
    : String(localized: "Video", bundle: .module)
}

/// 添付のファイル名。選んだファイルの名前があればそれ、無ければ (写真のライブラリから選んだ時など) 種類から作る (`image.png`・`video.mov` など)。
///
/// 添付には必ずファイル名を持たせる。タイトルも本文も無い添付のスニペットの表示名と、クリップボードに入れるファイルの名前に使うため。
public func snippetAttachmentFileName(originalFileName: String?, contentType: String) -> String {
  if let originalFileName = originalFileName?.trimmingCharacters(in: .whitespacesAndNewlines), !originalFileName.isEmpty {
    return originalFileName
  }
  let baseName = isSnippetAttachmentImage(contentType: contentType) ? "image" : "video"
  guard let filenameExtension = UTType(contentType)?.preferredFilenameExtension else {
    return baseName
  }
  return "\(baseName).\(filenameExtension)"
}

/// 一覧・ランチャーの行の 2 行目に出す、スニペットの中身の書き出し。本文のスニペットは本文の 1 行目、添付のスニペットは添付の種類の名前。
public func snippetContentSummary(snippet: Snippet) -> String {
  guard let attachmentContentType = snippet.attachmentContentType else {
    return snippetBodyFirstLine(body: snippet.body)
  }
  return snippetAttachmentKindLabel(contentType: attachmentContentType)
}

/// ファイルの選択 (`fileImporter`) で選んだファイルを、添付のデータ・種類 (UTType の識別子)・ファイル名として読む。
///
/// 選んだファイルはアプリの外にあることがあるため、読む間だけファイルへのアクセスの許可を得る (`startAccessingSecurityScopedResource()`)。
/// 画像・動画でないファイル (種類が分からないファイルを含む) は `SnippetValidationError.unsupportedAttachmentType` を、
/// 大きさの上限 (`snippetAttachmentMaximumByteCount`) を超えるファイルは `SnippetValidationError.attachmentTooLarge` を、読まずに投げる。上限を大きく超える動画をメモリに載せないため。
public func readSnippetAttachmentFile(fileURL: URL) throws -> (attachmentData: Data, attachmentContentType: String, attachmentFileName: String) {
  let isAccessingSecurityScopedResource = fileURL.startAccessingSecurityScopedResource()
  defer {
    if isAccessingSecurityScopedResource {
      fileURL.stopAccessingSecurityScopedResource()
    }
  }
  let resourceValues = try fileURL.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey])
  guard let contentType = resourceValues.contentType, snippetAttachmentAllowedContentTypes.contains(where: { contentType.conforms(to: $0) }) else {
    throw SnippetValidationError.unsupportedAttachmentType(contentType: resourceValues.contentType?.identifier ?? fileURL.pathExtension)
  }
  if let fileSize = resourceValues.fileSize, fileSize > snippetAttachmentMaximumByteCount {
    throw SnippetValidationError.attachmentTooLarge(maximumByteCount: snippetAttachmentMaximumByteCount)
  }
  return (try Data(contentsOf: fileURL), contentType.identifier, fileURL.lastPathComponent)
}

/// iOS のキーボードに並べてよい (本文のスニペットの) スニペットの、ストアの中の識別子。
///
/// キーボードは `insertText` で文字しか入れられないため、添付のスニペットを一覧とスニペットグループのメニューから外す (`documents/DIRECTION.md`「決めたこと」)。
/// 添付のスニペットは条件 (`attachmentContentType == nil`) で読み込みから外し、グループの項目とは `persistentModelID` で照合する。
/// 項目のスニペットの属性を読んで判定すると、添付のスニペットの行を読み込み、メモリの上限の小さいキーボードの拡張に添付を載せかねないため。
public func keyboardTextSnippetModelIDs(modelContext: ModelContext) throws -> Set<PersistentIdentifier> {
  Set(try modelContext.fetch(FetchDescriptor<Snippet>(predicate: #Predicate { $0.attachmentContentType == nil })).map(\.persistentModelID))
}
