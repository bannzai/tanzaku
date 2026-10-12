import SwiftData
import TanzakuKit
import UIKit

/// スニペットの中身をクリップボードに入れる。添付 (画像・動画) があれば添付をその種類 (UTType) のデータで、無ければ本文を入れる。同じスニペットで何度呼んでもクリップボードの中身は同じになる。
func copySnippetToPasteboard(snippet: Snippet) {
  if let attachmentData = snippet.attachmentData, let attachmentContentType = snippet.attachmentContentType {
    UIPasteboard.general.setItems([[attachmentContentType: attachmentData]])
  } else {
    UIPasteboard.general.string = snippet.body
  }
}

/// 一覧・詳細でスニペットをコピーし、使った日時を記録する (Mac のランチャーの最近使ったスニペットに出す)。
///
/// 使った日時の保存に失敗してもコピーは済んでおり、最近使ったスニペットに出ないだけのため、失敗を画面に出さない。
func copySnippetAndRecordUse(snippet: Snippet, modelContext: ModelContext) {
  copySnippetToPasteboard(snippet: snippet)
  try? recordSnippetUse(snippet: snippet, usedAt: .now, modelContext: modelContext)
}
