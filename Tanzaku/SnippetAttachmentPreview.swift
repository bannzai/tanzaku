import AppKit
import SwiftUI
import TanzakuKit

/// 添付 (本文の代わりの画像・動画) のプレビュー。画像は縮小して出し、動画は再生せずアイコンとファイル名にとどめる。
///
/// 動画を再生すると、編集画面・ランチャーを開くたびに添付の全体を読み込んで再生の準備をするため、出すのは何の動画かが分かるファイル名までにする。
struct SnippetAttachmentPreview: View {
  /// 添付のデータ。
  let attachmentData: Data
  /// 添付の種類 (UTType の識別子)。
  let attachmentContentType: String
  /// 添付のファイル名。
  let attachmentFileName: String

  var body: some View {
    if isSnippetAttachmentImage(contentType: attachmentContentType), let image = NSImage(data: attachmentData) {
      Image(nsImage: image)
        .resizable()
        .scaledToFit()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(Text(verbatim: attachmentFileName))
        .accessibilityIdentifier("snippet-attachment-preview")
    } else {
      VStack(spacing: 8) {
        Image(systemName: isSnippetAttachmentImage(contentType: attachmentContentType) ? "photo" : "film")
          .font(.system(size: 32))
          .foregroundStyle(.secondary)
        Text(verbatim: attachmentFileName)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
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
