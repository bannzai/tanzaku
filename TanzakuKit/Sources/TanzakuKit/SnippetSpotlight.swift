import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Spotlight の索引でスニペットの項目をまとめる domain。索引を入れ直す時に、この domain の項目だけを消すため。
public let snippetSpotlightDomainIdentifier = "com.bannzai.tanzaku.snippet"

/// スニペットを Spotlight の索引に入れる項目にする。項目の識別子は `Snippet.id` で、Spotlight で選ばれた時にアプリで開くスニペットを引くのに使う。
///
/// 索引に入れるのはタイトルとキーワードだけで、本文は入れない。本文には秘匿情報が入り得るため (`documents/DIRECTION.md`「決めたこと」、`.claude/rules/snippet-content-handling.md`)。
/// タイトルもキーワードも無いスニペットは、本文を入れずに出せる名前が無いため索引に入れず `nil` を返す。
public func snippetSpotlightSearchableItem(snippet: Snippet) -> CSSearchableItem? {
  guard let displayName = snippet.title ?? snippet.keyword else {
    return nil
  }
  let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
  attributeSet.title = displayName
  attributeSet.contentDescription = snippet.title == nil ? nil : snippet.keyword
  attributeSet.keywords = snippet.keyword.map { [$0] }
  return CSSearchableItem(uniqueIdentifier: snippet.id.uuidString, domainIdentifier: snippetSpotlightDomainIdentifier, attributeSet: attributeSet)
}
