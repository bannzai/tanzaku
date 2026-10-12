import Foundation
import SwiftData
import Testing

@testable import TanzakuKit

/// スニペットグループのキーワードの判定・メニューの項目の組み立て・キーワードを消すバックスペースの数を確かめる。
struct SnippetGroupKeywordMatchTests {
  /// スニペットとスニペットグループを置くインメモリのストア。
  private let modelContext: ModelContext

  /// テストごとに空のインメモリのストアを作る。
  init() throws {
    modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
  }

  /// 本文だけを持つスニペットをストアに入れる。
  private func insertSnippet(body: String) -> Snippet {
    let snippet = Snippet(body: body)
    modelContext.insert(snippet)
    return snippet
  }

  /// 添付 (画像) を持つスニペットをストアに入れる。添付のデータは画像として読めなくてよいため、偽の数バイトにする。
  private func insertAttachmentSnippet() -> Snippet {
    let snippet = Snippet(body: "")
    snippet.attachmentData = Data([0x89, 0x50, 0x4E, 0x47])
    snippet.attachmentContentType = "public.png"
    snippet.attachmentFileName = "dummy.png"
    modelContext.insert(snippet)
    return snippet
  }

  /// ストアに入れたスニペットを保存し、キーボードに並べてよい本文のスニペットを返す。キーボードはストアから読んだスニペットで判定するため、保存してから読む。
  private func textSnippetModelIDs() throws -> Set<PersistentIdentifier> {
    try modelContext.save()
    return try keyboardTextSnippetModelIDs(modelContext: modelContext)
  }

  /// キーワードとメニューに並べるスニペットを持つスニペットグループをストアに入れる。
  private func insertSnippetGroup(keyword: String, snippets: [Snippet]) throws -> SnippetGroup {
    let snippetGroup = SnippetGroup(name: "")
    try applySnippetGroupEdit(snippetGroup: snippetGroup, name: "dummy-group", keyword: keyword, snippets: snippets, modelContext: modelContext, now: .now)
    return snippetGroup
  }

  @Test("打った文字の末尾がキーワードと一致したグループを選び、前に打った文字は問わない", arguments: [";focus-app", "echo ;focus-app"])
  func matchesKeywordAtEndOfTypedText(typedText: String) throws {
    let snippetGroup = try insertSnippetGroup(keyword: ";focus-app", snippets: [insertSnippet(body: "make deploy")])

    #expect(snippetGroupMatchingTypedText(typedText: typedText, snippetGroups: [snippetGroup])?.id == snippetGroup.id)
  }

  @Test("キーワードを打ち終えていない・キーワードの後に打った・大文字と小文字が違う時は選ばない", arguments: [";focus-ap", ";focus-app ", ";FOCUS-APP", ""])
  func doesNotMatchOtherTypedText(typedText: String) throws {
    let snippetGroup = try insertSnippetGroup(keyword: ";focus-app", snippets: [insertSnippet(body: "make deploy")])

    #expect(snippetGroupMatchingTypedText(typedText: typedText, snippetGroups: [snippetGroup]) == nil)
  }

  @Test("片方のキーワードがもう片方の末尾になっている時は長い方を選ぶ")
  func prefersLongerKeyword() throws {
    let shortKeywordGroup = try insertSnippetGroup(keyword: ";env", snippets: [insertSnippet(body: "echo short")])
    let longKeywordGroup = try insertSnippetGroup(keyword: ";dev-env", snippets: [insertSnippet(body: "echo long")])

    #expect(snippetGroupMatchingTypedText(typedText: ";dev-env", snippetGroups: [shortKeywordGroup, longKeywordGroup])?.id == longKeywordGroup.id)
    #expect(snippetGroupMatchingTypedText(typedText: ";dev-env", snippetGroups: [longKeywordGroup, shortKeywordGroup])?.id == longKeywordGroup.id)
    #expect(snippetGroupMatchingTypedText(typedText: "x;env", snippetGroups: [shortKeywordGroup, longKeywordGroup])?.id == shortKeywordGroup.id)
  }

  @Test("キーワードが無いグループと、メニューに並べるスニペットが無いグループは選ばない")
  func skipsGroupsWithoutKeywordOrSnippets() throws {
    let noKeywordGroup = try insertSnippetGroup(keyword: "", snippets: [insertSnippet(body: "echo dummy")])
    let emptyGroup = try insertSnippetGroup(keyword: ";empty", snippets: [])

    #expect(snippetGroupMatchingTypedText(typedText: "", snippetGroups: [noKeywordGroup]) == nil)
    #expect(snippetGroupMatchingTypedText(typedText: ";empty", snippetGroups: [emptyGroup]) == nil)
  }

  @Test(
    "キーボードは入力欄のカーソルより前の文字の末尾でキーワードを判定する",
    arguments: [";dev", "dummy text\n;dev", "echo ;dev"]
  )
  func keyboardMatchesKeywordAtEndOfDocumentContext(documentContextBeforeInput: String) throws {
    let snippetGroup = try insertSnippetGroup(keyword: ";dev", snippets: [insertSnippet(body: "make deploy")])
    let keyboardTextSnippetIDs = try textSnippetModelIDs()

    #expect(
      snippetGroupMatchingDocumentContext(
        documentContextBeforeInput: documentContextBeforeInput,
        dismissedDocumentContextBeforeInput: nil,
        snippetGroups: [snippetGroup], textSnippetModelIDs: keyboardTextSnippetIDs
      )?.id == snippetGroup.id
    )
  }

  @Test("キーボードは入力欄が空・キーワードの後に打った・閉じた時と同じ文字の時はメニューを出さない")
  func keyboardDoesNotMatchOtherDocumentContext() throws {
    let snippetGroup = try insertSnippetGroup(keyword: ";dev", snippets: [insertSnippet(body: "make deploy")])
    let keyboardTextSnippetIDs = try textSnippetModelIDs()

    #expect(
      snippetGroupMatchingDocumentContext(documentContextBeforeInput: nil, dismissedDocumentContextBeforeInput: nil, snippetGroups: [snippetGroup], textSnippetModelIDs: keyboardTextSnippetIDs)
        == nil
    )
    #expect(
      snippetGroupMatchingDocumentContext(documentContextBeforeInput: ";dev ", dismissedDocumentContextBeforeInput: nil, snippetGroups: [snippetGroup], textSnippetModelIDs: keyboardTextSnippetIDs)
        == nil
    )
    #expect(
      snippetGroupMatchingDocumentContext(
        documentContextBeforeInput: "dummy ;dev",
        dismissedDocumentContextBeforeInput: "dummy ;dev",
        snippetGroups: [snippetGroup], textSnippetModelIDs: keyboardTextSnippetIDs
      ) == nil
    )
  }

  @Test("キーボードでメニューを閉じた後、文字が変わってまたキーワードで終われば出し直す")
  func keyboardMatchesAgainAfterDocumentContextChanges() throws {
    let snippetGroup = try insertSnippetGroup(keyword: ";dev", snippets: [insertSnippet(body: "make deploy")])
    let keyboardTextSnippetIDs = try textSnippetModelIDs()

    #expect(
      snippetGroupMatchingDocumentContext(
        documentContextBeforeInput: ";dev\n;dev",
        dismissedDocumentContextBeforeInput: ";dev",
        snippetGroups: [snippetGroup], textSnippetModelIDs: keyboardTextSnippetIDs
      )?.id == snippetGroup.id
    )
  }

  @Test("キーボードのメニューは添付のスニペットを除き、添付のスニペットしか無いグループは出さない")
  func keyboardExcludesAttachmentSnippets() throws {
    let textSnippet = insertSnippet(body: "make deploy")
    let attachmentSnippet = insertAttachmentSnippet()
    let mixedGroup = try insertSnippetGroup(keyword: ";mixed", snippets: [attachmentSnippet, textSnippet])
    let attachmentOnlyGroup = try insertSnippetGroup(keyword: ";shot", snippets: [attachmentSnippet])
    let keyboardTextSnippetIDs = try textSnippetModelIDs()

    #expect(keyboardTextSnippetIDs == [textSnippet.persistentModelID])
    #expect(keyboardSnippetGroupMenuSnippets(snippetGroup: mixedGroup, textSnippetModelIDs: keyboardTextSnippetIDs).map(\.id) == [textSnippet.id])
    #expect(
      snippetGroupMatchingDocumentContext(
        documentContextBeforeInput: ";mixed",
        dismissedDocumentContextBeforeInput: nil,
        snippetGroups: [mixedGroup, attachmentOnlyGroup],
        textSnippetModelIDs: keyboardTextSnippetIDs
      )?.id == mixedGroup.id
    )
    #expect(
      snippetGroupMatchingDocumentContext(
        documentContextBeforeInput: ";shot",
        dismissedDocumentContextBeforeInput: nil,
        snippetGroups: [mixedGroup, attachmentOnlyGroup],
        textSnippetModelIDs: keyboardTextSnippetIDs
      ) == nil
    )
  }

  @Test("Mac のメニューは添付のスニペットも並べる (⌘V で画像・動画も貼れるため)")
  func macMenuIncludesAttachmentSnippets() throws {
    let attachmentSnippet = insertAttachmentSnippet()
    let attachmentOnlyGroup = try insertSnippetGroup(keyword: ";shot", snippets: [attachmentSnippet])

    #expect(snippetGroupMatchingTypedText(typedText: ";shot", snippetGroups: [attachmentOnlyGroup])?.id == attachmentOnlyGroup.id)
    #expect(snippetGroupMenuSnippets(snippetGroup: attachmentOnlyGroup).map(\.id) == [attachmentSnippet.id])
  }

  @Test("メニューの項目はグループに登録した順に並び、スニペットを失った項目は除く")
  func menuSnippetsFollowItemOrder() throws {
    let deploySnippet = insertSnippet(body: "make deploy")
    let releaseSnippet = insertSnippet(body: "make release")
    let runTestSnippet = insertSnippet(body: "make run-test")
    let snippetGroup = try insertSnippetGroup(keyword: ";focus-app", snippets: [releaseSnippet, runTestSnippet, deploySnippet])
    // スニペットを消した後、削除ルールで項目が消えるまでの間に残る、スニペットを指さない項目を作る。
    let orphanItem = SnippetGroupItem(sortIndex: 1)
    modelContext.insert(orphanItem)
    snippetGroup.items?.append(orphanItem)

    #expect(snippetGroupMenuSnippets(snippetGroup: snippetGroup).map(\.id) == [releaseSnippet.id, runTestSnippet.id, deploySnippet.id])
  }

  @Test(
    "キーワードを消すバックスペースの数はキーワードの文字数",
    arguments: [(";focus-app", 10), (";dev", 4), (";café", 5), (";🇯🇵", 2)]
  )
  func backspaceCountIsCharacterCount(keyword: String, expectedCount: Int) {
    #expect(snippetGroupKeywordBackspaceCount(keyword: keyword) == expectedCount)
  }
}
