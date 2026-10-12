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

/// 写真のライブラリで選んだ画像・動画を、添付のデータと種類 (UTType の識別子) として読む。
///
/// 写真のライブラリの項目はファイル名を持たないため、ファイル名は返さない (保存の時に種類から作る。`snippetAttachmentFileName(originalFileName:contentType:)`)。
/// 画像・動画でない項目は `SnippetValidationError.unsupportedAttachmentType` を投げる。大きさは読んだ後の保存前の検査 (`validateSnippetContent`) で確かめる。
/// 写真のライブラリはデータの大きさを読む前に教えないため。
func loadSnippetAttachment(photosPickerItem: PhotosPickerItem) async throws -> (attachmentData: Data, attachmentContentType: String) {
  guard
    let contentType = photosPickerItem.supportedContentTypes.first(where: { contentType in
      snippetAttachmentAllowedContentTypes.contains { contentType.conforms(to: $0) }
    })
  else {
    throw SnippetValidationError.unsupportedAttachmentType(contentType: photosPickerItem.supportedContentTypes.first?.identifier ?? "")
  }
  guard let attachmentData = try await photosPickerItem.loadTransferable(type: Data.self) else {
    throw SnippetValidationError.unsupportedAttachmentType(contentType: contentType.identifier)
  }
  return (attachmentData, contentType.identifier)
}
