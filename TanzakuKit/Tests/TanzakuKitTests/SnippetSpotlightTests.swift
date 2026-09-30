import CoreSpotlight
import Foundation
import Testing

@testable import TanzakuKit

/// `snippetSpotlightSearchableItem(snippet:)` が索引に入れる項目を、タイトルとキーワードだけにして本文を入れないことを確かめる。
struct SnippetSpotlightTests {
  /// 偽の本文 (`.claude/rules/snippet-content-handling.md`)。索引の項目のどこにも出てはいけない。
  private let dummyBody = "export API_TOKEN=dummy-token-for-test"

  /// 項目の文字列の属性をすべて並べる。本文がどこにも入っていないことを確かめるため。
  private func textAttributes(searchableItem: CSSearchableItem) -> [String] {
    let attributeSet = searchableItem.attributeSet
    return [attributeSet.title, attributeSet.displayName, attributeSet.contentDescription, attributeSet.textContent].compactMap { $0 }
      + (attributeSet.keywords ?? [])
  }

  @Test("タイトルとキーワードを索引に入れ、スニペットの識別子で引けるようにする")
  func indexesTitleAndKeyword() throws {
    let snippet = Snippet(body: dummyBody)
    snippet.title = "トークンの雛形"
    snippet.keyword = "envkey"

    let searchableItem = try #require(snippetSpotlightSearchableItem(snippet: snippet))

    #expect(searchableItem.uniqueIdentifier == snippet.id.uuidString)
    #expect(searchableItem.domainIdentifier == snippetSpotlightDomainIdentifier)
    #expect(searchableItem.attributeSet.title == "トークンの雛形")
    #expect(searchableItem.attributeSet.contentDescription == "envkey")
    #expect(searchableItem.attributeSet.keywords == ["envkey"])
  }

  @Test("本文は索引の項目のどこにも入れない")
  func doesNotIndexBody() throws {
    let snippet = Snippet(body: dummyBody)
    snippet.title = "トークンの雛形"
    snippet.keyword = "envkey"

    let searchableItem = try #require(snippetSpotlightSearchableItem(snippet: snippet))

    #expect(textAttributes(searchableItem: searchableItem).allSatisfy { !$0.contains(dummyBody) && !$0.contains("dummy-token-for-test") })
    #expect(searchableItem.attributeSet.textContent == nil)
  }

  @Test("タイトルが無ければキーワードを項目の名前にする")
  func usesKeywordWhenTitleIsMissing() throws {
    let snippet = Snippet(body: dummyBody)
    snippet.keyword = "envkey"

    let searchableItem = try #require(snippetSpotlightSearchableItem(snippet: snippet))

    #expect(searchableItem.attributeSet.title == "envkey")
    #expect(searchableItem.attributeSet.contentDescription == nil)
    #expect(searchableItem.attributeSet.keywords == ["envkey"])
  }

  @Test("キーワードが無ければタイトルだけを入れる")
  func indexesTitleWithoutKeyword() throws {
    let snippet = Snippet(body: dummyBody)
    snippet.title = "トークンの雛形"

    let searchableItem = try #require(snippetSpotlightSearchableItem(snippet: snippet))

    #expect(searchableItem.attributeSet.title == "トークンの雛形")
    #expect(searchableItem.attributeSet.keywords == nil)
  }

  @Test("タイトルもキーワードも無いスニペットは、本文の 1 行目を名前にせず索引に入れない")
  func skipsSnippetWithoutTitleAndKeyword() {
    #expect(snippetSpotlightSearchableItem(snippet: Snippet(body: dummyBody)) == nil)
  }
}
