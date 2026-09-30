import CoreSpotlight
import TanzakuKit
import os

/// 直前に始めた索引の入れ直し。次の入れ直しはこれが終わるのを待ってから始める。
///
/// 削除と登録の組が重なると、古い入れ直しの登録が新しい入れ直しの削除の後に届き、消したスニペットが索引に残るため。
private var latestSnippetSpotlightIndexTask: Task<Void, Never>?

/// Spotlight の索引を、渡したスニペットだけが入った状態に入れ直す。失敗しても落とさず記録だけにする。
///
/// 消したスニペットの項目を残さないよう、スニペットの domain の項目をすべて消してから入れる。そのため何度呼んでも索引は同じになる。
/// 入れる項目はタイトルとキーワードだけで、本文は入れない (`snippetSpotlightSearchableItem(snippet:)`)。
/// 呼び出し元の取り消しでは止めず、前の入れ直しが終わってから順に行う。最後に呼んだ入れ直しが最後に索引へ届くようにするため。
func replaceSnippetSpotlightIndex(snippets: [Snippet]) async {
  let searchableItems = snippets.compactMap { snippetSpotlightSearchableItem(snippet: $0) }
  let previousTask = latestSnippetSpotlightIndexTask
  let task = Task {
    await previousTask?.value
    do {
      try await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [snippetSpotlightDomainIdentifier])
      try await CSSearchableIndex.default().indexSearchableItems(searchableItems)
    } catch {
      snippetSpotlightLogger.error("Failed to replace the Spotlight index: \(String(describing: error), privacy: .public)")
    }
  }
  latestSnippetSpotlightIndexTask = task
  await task.value
}

/// Spotlight の索引の失敗の記録。スニペットの本文は入れない (`.claude/rules/snippet-content-handling.md`)。
private let snippetSpotlightLogger = Logger(subsystem: "com.bannzai.tanzaku", category: "SnippetSpotlight")
