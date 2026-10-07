import Foundation
import SwiftData
import Testing

@testable import TanzakuKit

/// スニペットのキーワードの判定・スニペットグループのキーワードとの優先・キーワードを消すバックスペースの数を確かめる。
struct SnippetKeywordMatchTests {
  /// スニペットとスニペットグループを置くインメモリのストア。
  private let modelContext: ModelContext

  /// テストごとに空のインメモリのストアを作る。
  init() throws {
    modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
  }

  /// キーワードと本文を持つスニペットをストアに入れる。空のキーワードはキーワードなしになる。
  private func insertSnippet(keyword: String, body: String) throws -> Snippet {
    let snippet = Snippet(body: "")
    try applySnippetEdit(
      snippet: snippet,
      body: body,
      title: "",
      keyword: keyword,
      language: nil,
      color: nil,
      folder: nil,
      tagNames: [],
      modelContext: modelContext,
      now: .now
    )
    return snippet
  }

  /// キーワードとメニューに並べるスニペットを持つスニペットグループをストアに入れる。
  private func insertSnippetGroup(keyword: String, snippets: [Snippet]) throws -> SnippetGroup {
    let snippetGroup = SnippetGroup(name: "")
    try applySnippetGroupEdit(snippetGroup: snippetGroup, name: "dummy-group", keyword: keyword, snippets: snippets, modelContext: modelContext, now: .now)
    return snippetGroup
  }

  @Test("打った文字の末尾がキーワードと一致したスニペットを選び、前に打った文字は問わない", arguments: [";tkw", "echo ;tkw", "x;tkw"])
  func matchesKeywordAtEndOfTypedText(typedText: String) throws {
    let snippet = try insertSnippet(keyword: ";tkw", body: "dummy-command-for-test")

    #expect(snippetMatchingTypedText(typedText: typedText, snippets: [snippet], snippetGroups: [])?.id == snippet.id)
  }

  @Test("キーワードを打ち終えていない・キーワードの後に打った・大文字と小文字が違う時は選ばない", arguments: [";tk", ";tkw ", ";TKW", ""])
  func doesNotMatchOtherTypedText(typedText: String) throws {
    let snippet = try insertSnippet(keyword: ";tkw", body: "dummy-command-for-test")

    #expect(snippetMatchingTypedText(typedText: typedText, snippets: [snippet], snippetGroups: []) == nil)
  }

  @Test("キーワードが無いスニペットは選ばない")
  func skipsSnippetsWithoutKeyword() throws {
    let snippet = try insertSnippet(keyword: "", body: "dummy-command-for-test")

    #expect(snippetMatchingTypedText(typedText: "", snippets: [snippet], snippetGroups: []) == nil)
    #expect(snippetMatchingTypedText(typedText: "dummy-command-for-test", snippets: [snippet], snippetGroups: []) == nil)
  }

  @Test("片方のキーワードがもう片方の末尾になっている時は長い方を選ぶ")
  func prefersLongerKeyword() throws {
    let shortKeywordSnippet = try insertSnippet(keyword: ";env", body: "echo short")
    let longKeywordSnippet = try insertSnippet(keyword: ";dev-env", body: "echo long")

    #expect(
      snippetMatchingTypedText(typedText: ";dev-env", snippets: [shortKeywordSnippet, longKeywordSnippet], snippetGroups: [])?.id
        == longKeywordSnippet.id
    )
    #expect(
      snippetMatchingTypedText(typedText: ";dev-env", snippets: [longKeywordSnippet, shortKeywordSnippet], snippetGroups: [])?.id
        == longKeywordSnippet.id
    )
    #expect(
      snippetMatchingTypedText(typedText: "x;env", snippets: [shortKeywordSnippet, longKeywordSnippet], snippetGroups: [])?.id
        == shortKeywordSnippet.id
    )
  }

  @Test("スニペットグループのキーワードの方が長く一致している時は選ばず、グループのメニューに任せる")
  func yieldsToLongerSnippetGroupKeyword() throws {
    let snippet = try insertSnippet(keyword: ";env", body: "echo short")
    let snippetGroup = try insertSnippetGroup(keyword: ";dev-env", snippets: [try insertSnippet(keyword: "", body: "echo long")])

    #expect(snippetMatchingTypedText(typedText: ";dev-env", snippets: [snippet], snippetGroups: [snippetGroup]) == nil)
    #expect(snippetMatchingTypedText(typedText: "x;env", snippets: [snippet], snippetGroups: [snippetGroup])?.id == snippet.id)
  }

  @Test("スニペットのキーワードの方が長く一致している時は、スニペットグループがあってもスニペットを選ぶ")
  func winsOverShorterSnippetGroupKeyword() throws {
    let snippet = try insertSnippet(keyword: ";dev-env", body: "echo long")
    let snippetGroup = try insertSnippetGroup(keyword: ";env", snippets: [try insertSnippet(keyword: "", body: "echo short")])

    #expect(snippetMatchingTypedText(typedText: ";dev-env", snippets: [snippet], snippetGroups: [snippetGroup])?.id == snippet.id)
  }

  @Test("メニューに並べるスニペットが無いグループのキーワードには譲らない")
  func doesNotYieldToSnippetGroupWithoutSnippets() throws {
    let snippet = try insertSnippet(keyword: ";env", body: "echo short")
    let emptySnippetGroup = try insertSnippetGroup(keyword: ";dev-env", snippets: [])

    #expect(snippetMatchingTypedText(typedText: ";dev-env", snippets: [snippet], snippetGroups: [emptySnippetGroup])?.id == snippet.id)
  }

  @Test(
    "キーワードを消すバックスペースの数は、入力欄へ渡さない最後の 1 文字を除いた文字数",
    arguments: [(";tkw", 3), (";focus-app", 9), (";café", 4), (";", 0), ("", 0)]
  )
  func backspaceCountExcludesLastCharacter(keyword: String, expectedCount: Int) {
    #expect(snippetKeywordBackspaceCount(keyword: keyword) == expectedCount)
  }
}
