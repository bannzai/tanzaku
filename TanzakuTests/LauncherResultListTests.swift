import Foundation
import SwiftData
import TanzakuKit
import Testing

@testable import Tanzaku

/// ランチャーの結果の並べ方・選択の動かし方・本体の欄の出し分け・キーワードの太字の範囲を確かめる。
struct LauncherResultListTests {
  /// 結果に入れるスニペットを置くインメモリのストア。
  private let modelContext: ModelContext

  /// テストごとに空のインメモリのストアを作る。
  init() throws {
    modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
  }

  /// 本文とキーワードだけを持つスニペットをストアに入れる。
  private func makeSnippet(body: String, keyword: String? = nil) -> Snippet {
    let snippet = Snippet(body: body)
    snippet.keyword = keyword
    modelContext.insert(snippet)
    return snippet
  }

  @Test("キーワードが一致した欄、意味が近い欄の順につなげ、各欄の中の順は検索の結果のまま")
  func selectableSnippetsKeepSectionOrder() {
    let exactMatchedSnippet = makeSnippet(body: "echo dummy exact", keyword: "env")
    let prefixMatchedSnippet = makeSnippet(body: "echo dummy prefix", keyword: "envkey")
    let firstSemanticSnippet = makeSnippet(body: "echo dummy semantic 1")
    let secondSemanticSnippet = makeSnippet(body: "echo dummy semantic 2")
    let searchResult = SnippetSearchResult(
      keywordMatches: [
        SnippetKeywordMatch(snippet: exactMatchedSnippet, kind: .keywordExact),
        SnippetKeywordMatch(snippet: prefixMatchedSnippet, kind: .keywordPrefix),
      ],
      semanticMatches: [firstSemanticSnippet, secondSemanticSnippet]
    )

    #expect(
      launcherSelectableSnippets(searchResult: searchResult).map(\.id)
        == [exactMatchedSnippet.id, prefixMatchedSnippet.id, firstSemanticSnippet.id, secondSemanticSnippet.id]
    )
    #expect(launcherSelectedSnippet(searchResult: searchResult, selectedSnippetIndex: 2)?.id == firstSemanticSnippet.id)
  }

  @Test("選んでいる位置が無い・結果の範囲の外なら選んでいるスニペットは無い")
  func selectedSnippetOutOfRangeIsNil() {
    let searchResult = SnippetSearchResult(keywordMatches: [], semanticMatches: [makeSnippet(body: "echo dummy")])

    #expect(launcherSelectedSnippet(searchResult: searchResult, selectedSnippetIndex: nil) == nil)
    #expect(launcherSelectedSnippet(searchResult: searchResult, selectedSnippetIndex: 1) == nil)
    #expect(launcherSelectedSnippet(searchResult: searchResult, selectedSnippetIndex: -1) == nil)
  }

  @Test("入力を変えずに結果を入れ替えた時は、選んでいたスニペットが残っていればその位置を選び、無ければ先頭を選ぶ")
  func selectionFollowsSnippetAfterResultUpdate() {
    let keywordMatchedSnippet = makeSnippet(body: "echo dummy keyword", keyword: "env")
    let selectedSnippet = makeSnippet(body: "echo dummy selected", keyword: "envkey")
    let semanticSnippet = makeSnippet(body: "echo dummy semantic")
    let updatedSearchResult = SnippetSearchResult(
      keywordMatches: [
        SnippetKeywordMatch(snippet: keywordMatchedSnippet, kind: .keywordExact),
        SnippetKeywordMatch(snippet: selectedSnippet, kind: .keywordPrefix),
      ],
      semanticMatches: [semanticSnippet]
    )

    #expect(launcherSelectionIndexAfterResultUpdate(searchResult: updatedSearchResult, selectedSnippetID: selectedSnippet.id) == 1)
    #expect(launcherSelectionIndexAfterResultUpdate(searchResult: updatedSearchResult, selectedSnippetID: UUID()) == 0)
    #expect(launcherSelectionIndexAfterResultUpdate(searchResult: updatedSearchResult, selectedSnippetID: nil) == 0)
    #expect(
      launcherSelectionIndexAfterResultUpdate(searchResult: SnippetSearchResult(keywordMatches: [], semanticMatches: []), selectedSnippetID: selectedSnippet.id)
        == nil
    )
  }

  @Test("↑↓ は端で止まり、回り込まない。選んでいなければ先頭、結果が無ければ選ばない")
  func movedSelectionIndexIsClamped() {
    #expect(launcherMovedSelectionIndex(currentIndex: 0, offset: 1, count: 3) == 1)
    #expect(launcherMovedSelectionIndex(currentIndex: 2, offset: 1, count: 3) == 2)
    #expect(launcherMovedSelectionIndex(currentIndex: 0, offset: -1, count: 3) == 0)
    #expect(launcherMovedSelectionIndex(currentIndex: nil, offset: 1, count: 3) == 0)
    #expect(launcherMovedSelectionIndex(currentIndex: 1, offset: 1, count: 0) == nil)
  }

  @Test("入力が空白だけなら何も出さず、入力があれば結果の有無で結果の欄と結果なしの案内を出し分ける")
  func contentStateDependsOnQueryAndResults() {
    let emptySearchResult = SnippetSearchResult(keywordMatches: [], semanticMatches: [])
    let searchResult = SnippetSearchResult(keywordMatches: [], semanticMatches: [makeSnippet(body: "echo dummy")])

    #expect(launcherContentState(query: " \n", searchResult: searchResult) == .idle)
    #expect(launcherContentState(query: "env", searchResult: searchResult) == .results)
    #expect(launcherContentState(query: "ステージングの DB につなぐ", searchResult: emptySearchResult) == .empty)
  }

  @Test("キーワードの完全一致・前方一致は入力の文字数だけ先頭を太字にし、タイトル・本文の一致は太字にしない")
  func keywordHighlightSplitsMatchedPrefix() {
    #expect(
      launcherKeywordHighlight(keyword: "envkey", query: " env ", matchKind: .keywordPrefix)
        == LauncherKeywordHighlight(matchedPrefix: "env", remainder: "key")
    )
    #expect(
      launcherKeywordHighlight(keyword: "ENV", query: "env", matchKind: .keywordExact)
        == LauncherKeywordHighlight(matchedPrefix: "ENV", remainder: "")
    )
    #expect(
      launcherKeywordHighlight(keyword: "ghsec", query: "secrets", matchKind: .titleOrBody)
        == LauncherKeywordHighlight(matchedPrefix: "", remainder: "ghsec")
    )
    #expect(
      launcherKeywordHighlight(keyword: "ghsec", query: "ghsec", matchKind: nil)
        == LauncherKeywordHighlight(matchedPrefix: "", remainder: "ghsec")
    )
  }

  @Test("実際の検索の結果を、キーワードの完全一致・前方一致・タイトルと本文の一致の順に選べる")
  func searchResultIsSelectableInDisplayOrder() throws {
    let bodyMatchedSnippet = makeSnippet(body: "export DUMMY_ENV=dummy-token-for-test")
    let prefixMatchedSnippet = makeSnippet(body: "echo dummy", keyword: "envkey")
    let exactMatchedSnippet = makeSnippet(body: "echo dummy", keyword: "env")

    let searchResult = try searchSnippets(query: "env", modelContext: modelContext, embedder: nil)

    #expect(launcherContentState(query: "env", searchResult: searchResult) == .results)
    #expect(
      launcherSelectableSnippets(searchResult: searchResult).map(\.id) == [exactMatchedSnippet.id, prefixMatchedSnippet.id, bodyMatchedSnippet.id]
    )
  }
}
