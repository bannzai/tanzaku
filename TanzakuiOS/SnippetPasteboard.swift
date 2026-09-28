import UIKit

/// スニペットの本文をクリップボードに入れる。同じ本文で何度呼んでもクリップボードの中身は同じになる。
func copySnippetBodyToPasteboard(body: String) {
  UIPasteboard.general.string = body
}
