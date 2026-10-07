import Foundation
import SwiftData
import Testing

@testable import TanzakuKit

/// 言語モデルが返した文字列からのタイトル・タグの取り出しと、スニペットに付ける条件を確かめる。
struct SnippetGeneratedMetadataTests {
  /// スニペットとタグを置くインメモリのストア。
  private let modelContext: ModelContext

  /// テストごとに空のインメモリのストアを作る。
  init() throws {
    modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
  }

  /// 本文・タイトル・タグを持つスニペットをストアに入れる。
  private func insertSnippet(body: String, title: String, tagNames: [String]) throws -> Snippet {
    let snippet = Snippet(body: "")
    try applySnippetEdit(
      snippet: snippet,
      body: body,
      title: title,
      keyword: "",
      language: nil,
      color: nil,
      folder: nil,
      tagNames: tagNames,
      modelContext: modelContext,
      now: Date(timeIntervalSince1970: 0)
    )
    return snippet
  }

  @Test(
    "タイトルは空でない最初の行から、囲みの引用符・かぎ括弧と前後の空白を除いて取り出す",
    arguments: [
      ("Kill the tmux window", "Kill the tmux window"),
      ("  \"Kill the tmux window\"  ", "Kill the tmux window"),
      ("「tmux のウィンドウを閉じる」", "tmux のウィンドウを閉じる"),
      ("\n\nKill the tmux window\nIt closes the current window.", "Kill the tmux window"),
    ]
  )
  func extractsTitleFromFirstLine(generatedText: String, expectedTitle: String) {
    #expect(generatedSnippetTitle(generatedText: generatedText) == expectedTitle)
  }

  @Test("タイトルにできる文字が無い時は nil を返す", arguments: ["", "  \n\t\n", "\"\""])
  func returnsNilWithoutTitle(generatedText: String) {
    #expect(generatedSnippetTitle(generatedText: generatedText) == nil)
  }

  @Test("長いタイトルは最大の文字数で切り、切った末尾の空白を除く")
  func truncatesLongTitle() {
    #expect(generatedSnippetTitle(generatedText: String(repeating: "a", count: generatedSnippetTitleMaxLength + 10))?.count == generatedSnippetTitleMaxLength)
    #expect(
      generatedSnippetTitle(generatedText: String(repeating: "a", count: generatedSnippetTitleMaxLength - 1) + " dummy")
        == String(repeating: "a", count: generatedSnippetTitleMaxLength - 1)
    )
  }

  @Test(
    "タグはカンマか改行で区切り、先頭の # と - ・空の名前・重複した名前を除く",
    arguments: [
      ("shell, tmux", ["shell", "tmux"]),
      ("#shell、#tmux", ["shell", "tmux"]),
      ("- shell\n- tmux\n", ["shell", "tmux"]),
      ("shell, , shell, github-actions", ["shell", "github-actions"]),
      ("", []),
    ] as [(String, [String])]
  )
  func extractsTagNames(generatedText: String, expectedTagNames: [String]) {
    #expect(generatedSnippetTagNames(generatedText: generatedText) == expectedTagNames)
  }

  @Test("タグは最大の数までにし、長すぎる名前はタグにしない")
  func limitsTagNames() {
    #expect(generatedSnippetTagNames(generatedText: "a, b, c, d, e") == ["a", "b", "c"])
    #expect(
      generatedSnippetTagNames(generatedText: "shell, " + String(repeating: "a", count: generatedSnippetTagNameMaxLength + 1) + ", tmux")
        == ["shell", "tmux"]
    )
  }

  @Test("言語モデルに渡す既にあるタグは、付けたスニペットが多い順に最大の数までで、長すぎる名前は渡さない")
  func limitsExistingTagNamesForPrompt() throws {
    _ = try insertSnippet(body: "dummy-command-1", title: "", tagNames: ["shell", "tmux"])
    _ = try insertSnippet(body: "dummy-command-2", title: "", tagNames: ["shell", "auth", String(repeating: "a", count: generatedSnippetTagNameMaxLength + 1)])
    _ = try insertSnippet(body: "dummy-command-3", title: "", tagNames: (0..<generatedSnippetTagPromptExistingTagLimit).map { "tag-\($0)" })
    // タグから付けたスニペットをたどる向きのリレーションを、ストアに確定させてから数える。
    try modelContext.save()

    let existingTagNames = generatedSnippetTagPromptExistingTagNames(tags: try modelContext.fetch(FetchDescriptor<SchemaV2.Tag>()))

    #expect(existingTagNames.count == generatedSnippetTagPromptExistingTagLimit)
    #expect(Array(existingTagNames.prefix(3)) == ["shell", "auth", "tag-0"])
    #expect(existingTagNames.allSatisfy { $0.count <= generatedSnippetTagNameMaxLength })
  }

  @Test("タイトルが無く本文が変わっていないスニペットには、作ったタイトルを付け、更新日時は変えない")
  func appliesTitleToUntitledSnippet() throws {
    let snippet = try insertSnippet(body: "dummy-command-for-test", title: "", tagNames: [])

    #expect(applyGeneratedSnippetTitle(snippet: snippet, generatedText: "Dummy command", sourceBody: "dummy-command-for-test"))
    #expect(snippet.title == "Dummy command")
    #expect(snippet.updatedAt == Date(timeIntervalSince1970: 0))
  }

  @Test("タイトルがあるスニペット・本文が変わったスニペット・タイトルにできない応答では、タイトルを付けない")
  func doesNotApplyTitle() throws {
    let titledSnippet = try insertSnippet(body: "dummy-command-for-test", title: "My title", tagNames: [])
    #expect(!applyGeneratedSnippetTitle(snippet: titledSnippet, generatedText: "Dummy command", sourceBody: "dummy-command-for-test"))
    #expect(titledSnippet.title == "My title")

    let editedSnippet = try insertSnippet(body: "dummy-command-for-test edited", title: "", tagNames: [])
    #expect(!applyGeneratedSnippetTitle(snippet: editedSnippet, generatedText: "Dummy command", sourceBody: "dummy-command-for-test"))
    #expect(editedSnippet.title == nil)

    let untitledSnippet = try insertSnippet(body: "dummy-command-for-test", title: "", tagNames: [])
    #expect(!applyGeneratedSnippetTitle(snippet: untitledSnippet, generatedText: "  \n", sourceBody: "dummy-command-for-test"))
    #expect(untitledSnippet.title == nil)
  }

  @Test("タグが無く本文が変わっていないスニペットには、作ったタグを付け、同じ名前のタグがあればそれを使う")
  func appliesTagsToUntaggedSnippet() throws {
    let taggedSnippet = try insertSnippet(body: "dummy-other-command", title: "", tagNames: ["shell"])
    let snippet = try insertSnippet(body: "dummy-command-for-test", title: "", tagNames: [])

    #expect(try applyGeneratedSnippetTags(snippet: snippet, generatedText: "shell, tmux", sourceBody: "dummy-command-for-test", modelContext: modelContext))
    #expect(Set((snippet.tags ?? []).map(\.name)) == ["shell", "tmux"])
    #expect((snippet.tags ?? []).first { $0.name == "shell" }?.id == (taggedSnippet.tags ?? []).first?.id)
    #expect(try modelContext.fetchCount(FetchDescriptor<SchemaV2.Tag>()) == 2)
    #expect(snippet.updatedAt == Date(timeIntervalSince1970: 0))
  }

  @Test("タグがあるスニペット・本文が変わったスニペット・タグにできない応答では、タグを付けず、タグも作らない")
  func doesNotApplyTags() throws {
    let taggedSnippet = try insertSnippet(body: "dummy-command-for-test", title: "", tagNames: ["mine"])
    #expect(try !applyGeneratedSnippetTags(snippet: taggedSnippet, generatedText: "shell", sourceBody: "dummy-command-for-test", modelContext: modelContext))
    #expect((taggedSnippet.tags ?? []).map(\.name) == ["mine"])

    let editedSnippet = try insertSnippet(body: "dummy-command-for-test edited", title: "", tagNames: [])
    #expect(try !applyGeneratedSnippetTags(snippet: editedSnippet, generatedText: "shell", sourceBody: "dummy-command-for-test", modelContext: modelContext))

    let untaggedSnippet = try insertSnippet(body: "dummy-command-for-test", title: "", tagNames: [])
    #expect(try !applyGeneratedSnippetTags(snippet: untaggedSnippet, generatedText: " , ", sourceBody: "dummy-command-for-test", modelContext: modelContext))

    #expect(try modelContext.fetchCount(FetchDescriptor<SchemaV2.Tag>()) == 1)
  }
}
