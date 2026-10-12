import PhotosUI
import SwiftUI
import TanzakuKit
import UIKit

/// 添付 (本文の代わりの画像・動画) のプレビュー。画像は縮小して出し、動画は再生せずアイコンとファイル名にとどめる (Mac の `SnippetAttachmentPreview` と同じ)。
///
/// 動画を再生すると、編集画面・詳細を開くたびに添付の全体を読み込んで再生の準備をするため、出すのは何の動画かが分かるファイル名までにする。
struct SnippetAttachmentPreview: View {
  /// 添付のデータ。
  let attachmentData: Data
  /// 添付の種類 (UTType の識別子)。
  let attachmentContentType: String
  /// 添付のファイル名。
  let attachmentFileName: String

  var body: some View {
    if isSnippetAttachmentImage(contentType: attachmentContentType), let image = UIImage(data: attachmentData) {
      Image(uiImage: image)
        .resizable()
        .scaledToFit()
        // 縦に長い画像で編集画面の残りの項目が画面の外へ押し出されないよう、高さを抑える。240pt は iPhone SE の縦向きの画面の半分弱。
        .frame(maxWidth: .infinity, maxHeight: 240)
        .accessibilityLabel(Text(verbatim: attachmentFileName))
        .accessibilityIdentifier("snippet-attachment-preview")
    } else {
      Label {
        Text(verbatim: attachmentFileName)
          .lineLimit(1)
          .truncationMode(.middle)
      } icon: {
        Image(systemName: isSnippetAttachmentImage(contentType: attachmentContentType) ? "photo" : "film")
      }
      .accessibilityIdentifier("snippet-attachment-preview")
    }
  }
}

/// スニペットの添付のプレビュー。添付が無いスニペットには何も出さない。
struct SnippetAttachmentPreviewOfSnippet: View {
  /// プレビューするスニペット。
  let snippet: Snippet

  var body: some View {
    if let attachmentData = snippet.attachmentData, let attachmentContentType = snippet.attachmentContentType {
      SnippetAttachmentPreview(
        attachmentData: attachmentData,
        attachmentContentType: attachmentContentType,
        attachmentFileName: snippet.attachmentFileName ?? snippetAttachmentFileName(originalFileName: nil, contentType: attachmentContentType)
      )
    }
  }
}

/// 写真のライブラリで選んだ画像・動画を、ファイルとして受け取ったもの。データの全体をメモリに載せる前に大きさを確かめるため、データ (`Data`) ではなくファイルで受け取る。
/// 写真のライブラリはメインスレッドの外で受け取りの処理を呼ぶため nonisolated にする。
private nonisolated struct PhotosPickerAttachmentFile: Transferable {
  /// 受け取ったファイルを写した、このアプリの一時フォルダの中のファイル。
  let fileURL: URL

  /// 写真のライブラリが渡すファイルは受け取りの処理の間しか残らないため、一時フォルダへ写す。画像・動画のどちらも受け取れるよう、すべてのファイル (`.item`) を受け付け、種類は読む時に確かめる。
  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(importedContentType: .item) { receivedFile in
      let directoryURL = URL.temporaryDirectory.appending(path: "PhotosPickerAttachments/\(UUID().uuidString)", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
      let fileURL = directoryURL.appending(path: receivedFile.file.lastPathComponent, directoryHint: .notDirectory)
      try FileManager.default.copyItem(at: receivedFile.file, to: fileURL)
      return PhotosPickerAttachmentFile(fileURL: fileURL)
    }
  }
}

/// 写真のライブラリで選んだ画像・動画を、添付のデータ・種類 (UTType の識別子)・ファイル名として読む。
///
/// ファイルとして受け取ってから `readSnippetAttachmentFile(fileURL:)` で読むため、画像・動画でない項目と大きさの上限を超える項目は、データを読まずに `SnippetValidationError` を投げる。
/// 数 GB の動画を選んでもメモリに載せずに断るため。読んだ後は一時フォルダに写したファイルを消す。
func loadSnippetAttachment(photosPickerItem: PhotosPickerItem) async throws -> (attachmentData: Data, attachmentContentType: String, attachmentFileName: String) {
  guard let attachmentFile = try await photosPickerItem.loadTransferable(type: PhotosPickerAttachmentFile.self) else {
    throw SnippetValidationError.unsupportedAttachmentType(contentType: photosPickerItem.supportedContentTypes.first?.identifier ?? "")
  }
  defer {
    try? FileManager.default.removeItem(at: attachmentFile.fileURL.deletingLastPathComponent())
  }
  return try readSnippetAttachmentFile(fileURL: attachmentFile.fileURL)
}
