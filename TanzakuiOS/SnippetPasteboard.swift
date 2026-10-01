import SwiftData
import TanzakuKit
import UIKit

/// スニペットの本文をクリップボードに入れる。同じ本文で何度呼んでもクリップボードの中身は同じになる。
func copySnippetBodyToPasteboard(body: String) {
  UIPasteboard.general.string = body
}

/// 一覧・詳細でスニペットをコピーし、使った日時を記録する (Mac のランチャーの最近使ったスニペットに出す)。
///
/// 使った日時の保存に失敗してもコピーは済んでおり、最近使ったスニペットに出ないだけのため、失敗を画面に出さない。
func copySnippetBodyAndRecordUse(snippet: Snippet, modelContext: ModelContext) {
  copySnippetBodyToPasteboard(body: snippet.body)
  try? recordSnippetUse(snippet: snippet, usedAt: .now, modelContext: modelContext)
}
