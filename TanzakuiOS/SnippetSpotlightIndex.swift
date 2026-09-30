import CoreSpotlight
import TanzakuKit
import os

/// Spotlight の索引を、渡したスニペットだけが入った状態に入れ直す。失敗しても落とさず記録だけにする。
///
/// 消したスニペットの項目を残さないよう、スニペットの domain の項目をすべて消してから入れる。そのため何度呼んでも索引は同じになる。
/// 入れる項目はタイトルとキーワードだけで、本文は入れない (`snippetSpotlightSearchableItem(snippet:)`)。
func replaceSnippetSpotlightIndex(snippets: [Snippet]) async {
  let searchableItems = snippets.compactMap { snippetSpotlightSearchableItem(snippet: $0) }
  do {
    try await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [snippetSpotlightDomainIdentifier])
    try await CSSearchableIndex.default().indexSearchableItems(searchableItems)
  } catch {
    snippetSpotlightLogger.error("Failed to replace the Spotlight index: \(String(describing: error), privacy: .public)")
  }
}

/// Spotlight の索引の失敗の記録。スニペットの本文は入れない (`.claude/rules/snippet-content-handling.md`)。
private let snippetSpotlightLogger = Logger(subsystem: "com.bannzai.tanzaku", category: "SnippetSpotlight")
