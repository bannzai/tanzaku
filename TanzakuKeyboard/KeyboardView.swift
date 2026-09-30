import SwiftData
import SwiftUI
import TanzakuKit
import UIKit

/// 上の端の帯 (スニペットの一覧を開くボタン・検索の入力・スニペットグループの名前) の高さ。44pt はタップできる領域の最小の大きさ (Human Interface Guidelines)。
private let keyboardBarHeight: CGFloat = 44
/// 文字のキーの 4 段の高さ。216pt は iPhone の縦向きの標準のキーボードのキーの領域の高さで、ほかのキーボードから切り替えた時に入力欄の見える範囲を変えないため。
private let keyboardKeysHeight: CGFloat = 216
/// スニペットの一覧・スニペットグループのメニューの高さ。44pt の行を 3 行半見せ、続きがあることをスクロールの前に分からせるため。
private let keyboardPanelHeight: CGFloat = 154
/// 文字を打つ時のキーボードの高さ。
let keyboardTypingHeight = keyboardBarHeight + keyboardKeysHeight

/// キーボードが読むストア。開けなかった時・読めなかった時はその理由。
///
/// フルアクセスが無い時は共有コンテナを開けないことがあり、開けても読めないことがあるため、開いた後に 1 回読んで確かめる (`documents/DIRECTION.md`「決めたこと」)。
/// キーボードからはストアへ書き込まない (`documents/data-model.md`「ストアの分け方」)。
let keyboardModelContainerResult: Result<ModelContainer, any Error> = iosModelContainerResult.flatMap { modelContainer in
  Result {
    _ = try modelContainer.mainContext.fetchCount(FetchDescriptor<Snippet>())
    return modelContainer
  }
}

/// キーボードの画面。上の端の帯、スニペットの一覧またはスニペットグループのメニュー、文字のキーを縦に並べる。
///
/// 入力欄の文字は `textDocumentProxy` から読み、キーワードの判定だけに使う。保存・ログ出力・送信をしない (`documents/PROJECT.md`「iOS > カスタムキーボード」)。
struct KeyboardView: View {
  /// 入口から受け取る状態。
  let keyboardHostState: KeyboardHostState
  /// 入力欄。文字を入れる・消す・カーソルより前の文字を読むのに使う。
  let textDocumentProxy: any UITextDocumentProxy
  /// 次のキーボードへ切り替える (`UIInputViewController.advanceToNextInputMode()`)。
  let advanceToNextInputMode: () -> Void
  /// キーボードの高さを変える。スニペットの一覧・メニューを出す時だけ高くする。
  let setKeyboardHeight: (CGFloat) -> Void

  /// 文字のキーの面。
  @State private var keyPage = KeyboardKeyPage.letters
  /// 次の 1 文字を大文字にするか。
  @State private var isShifted = false
  /// スニペットの一覧を出しているか。出している間、文字のキーは検索の入力へ打つ。
  @State private var isShowingSnippets = false
  /// スニペットの一覧の検索の入力。キーボードの中だけに持ち、一覧を閉じると捨てる。
  @State private var snippetSearchQuery = ""
  /// メニューを出しているスニペットグループ。
  @State private var matchedSnippetGroup: SnippetGroup?
  /// メニューを閉じた時の入力欄のカーソルより前の文字。同じ文字の間はメニューを出し直さないために、キーボードを出している間だけメモリに持つ。
  @State private var dismissedDocumentContextBeforeInput: String?

  var body: some View {
    let isShowingPanel = isShowingSnippets || matchedSnippetGroup != nil
    VStack(spacing: 0) {
      keyboardBar
        .frame(height: keyboardBarHeight)
      if isShowingPanel {
        keyboardPanel
          .frame(height: keyboardPanelHeight)
      }
      KeyboardKeysView(
        keyPage: keyPage,
        isShifted: isShifted,
        showsInputModeSwitchKey: keyboardHostState.needsInputModeSwitchKey,
        onInsert: insertKeyText(text:),
        onDelete: deleteBackward,
        onShift: {
          isShifted.toggle()
        },
        onKeyPageChange: { keyPage in
          self.keyPage = keyPage
        },
        onReturn: pressReturn,
        onAdvanceToNextInputMode: advanceToNextInputMode
      )
      .frame(height: keyboardKeysHeight)
    }
    .onChange(of: isShowingPanel, initial: true) {
      setKeyboardHeight(isShowingPanel ? keyboardTypingHeight + keyboardPanelHeight : keyboardTypingHeight)
    }
    .onChange(of: keyboardHostState.textChangeCount, initial: true) {
      refreshMatchedSnippetGroup()
    }
  }

  /// 上の端の帯。スニペットグループのメニューを出している時はグループの名前、スニペットの一覧を出している時は検索の入力、それ以外は一覧を開くボタンを出す。
  @ViewBuilder
  private var keyboardBar: some View {
    HStack(spacing: 8) {
      if isShowingSnippets {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
        if snippetSearchQuery.isEmpty {
          Text("Search snippets")
            .foregroundStyle(.secondary)
        } else {
          Text(verbatim: snippetSearchQuery)
            .lineLimit(1)
            .truncationMode(.head)
          Button("Clear", systemImage: "xmark.circle.fill") {
            snippetSearchQuery = ""
          }
          .labelStyle(.iconOnly)
          .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        Button("Done") {
          closeSnippets()
        }
        .fontWeight(.semibold)
      } else if let matchedSnippetGroup {
        Image(systemName: "list.bullet.rectangle")
          .foregroundStyle(.secondary)
        Text(verbatim: matchedSnippetGroup.name)
          .fontWeight(.semibold)
          .lineLimit(1)
        Text(verbatim: matchedSnippetGroup.keyword ?? "")
          .font(.subheadline.monospaced())
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Spacer(minLength: 0)
        Button("Close", systemImage: "xmark") {
          dismissSnippetGroupMenu()
        }
        .labelStyle(.iconOnly)
      } else {
        Button {
          matchedSnippetGroup = nil
          isShowingSnippets = true
        } label: {
          Label("Snippets", systemImage: "rectangle.portrait.on.rectangle.portrait")
        }
        Spacer(minLength: 0)
      }
    }
    .padding(.horizontal, 12)
    .tint(.primary)
  }

  /// キーの上に出す欄。スニペットの一覧、またはスニペットグループのメニュー。
  @ViewBuilder
  private var keyboardPanel: some View {
    if isShowingSnippets {
      switch keyboardModelContainerResult {
      case .success(let modelContainer):
        KeyboardSnippetList(searchQuery: snippetSearchQuery) { snippet in
          textDocumentProxy.insertText(snippet.body)
          closeSnippets()
        }
        .modelContainer(modelContainer)
      case .failure(let error):
        KeyboardStoreUnavailableView(hasFullAccess: keyboardHostState.hasFullAccess, error: error)
      }
    } else if let matchedSnippetGroup {
      KeyboardSnippetGroupMenu(snippetGroup: matchedSnippetGroup) { snippet in
        insertSnippetGroupItem(snippet: snippet, snippetGroup: matchedSnippetGroup)
      }
    }
  }

  /// 文字のキーで打った文字を、スニペットの一覧を出している間は検索の入力へ、それ以外は入力欄へ入れる。大文字にするのは 1 文字だけ。
  private func insertKeyText(text: String) {
    if isShowingSnippets {
      snippetSearchQuery += text
    } else {
      textDocumentProxy.insertText(text)
      refreshMatchedSnippetGroupAfterKeyInput()
    }
    isShifted = false
  }

  /// 削除のキー。スニペットの一覧を出している間は検索の入力の末尾の 1 文字、それ以外は入力欄のカーソルの前の 1 文字を消す。
  private func deleteBackward() {
    if isShowingSnippets {
      snippetSearchQuery = String(snippetSearchQuery.dropLast())
    } else {
      textDocumentProxy.deleteBackward()
      refreshMatchedSnippetGroupAfterKeyInput()
    }
  }

  /// 改行のキー。スニペットの一覧を出している間は一覧を閉じ、それ以外は入力欄に改行を入れる。
  private func pressReturn() {
    if isShowingSnippets {
      closeSnippets()
    } else {
      insertKeyText(text: "\n")
    }
  }

  /// スニペットの一覧を閉じ、検索の入力を捨てる。
  private func closeSnippets() {
    isShowingSnippets = false
    snippetSearchQuery = ""
    refreshMatchedSnippetGroup()
  }

  /// スニペットグループのメニューを閉じる。打ったキーワードは入力欄に残す (Mac のメニューの Esc と同じ)。
  private func dismissSnippetGroupMenu() {
    dismissedDocumentContextBeforeInput = textDocumentProxy.documentContextBeforeInput
    matchedSnippetGroup = nil
  }

  /// メニューで選んだスニペットを、打ったキーワードを消してから入れる。
  ///
  /// メニューを出した後に入力欄の文字がキーワードで終わらなくなっていたら (ほかの操作で変わった)、関係の無い文字を消さないよう何もせずメニューを閉じる。
  /// 文字を選んでいる時も何もしない。最初の `deleteBackward()` がキーワードではなく選んだ文字を消すため。
  private func insertSnippetGroupItem(snippet: Snippet, snippetGroup: SnippetGroup) {
    defer {
      matchedSnippetGroup = nil
    }
    guard let keyword = snippetGroup.keyword,
      textDocumentProxy.documentContextBeforeInput?.hasSuffix(keyword) == true,
      textDocumentProxy.selectedText?.isEmpty ?? true
    else {
      return
    }
    for _ in 0..<snippetGroupKeywordBackspaceCount(keyword: keyword) {
      textDocumentProxy.deleteBackward()
    }
    textDocumentProxy.insertText(snippet.body)
  }

  /// 入力欄のカーソルより前の文字から、メニューを出すスニペットグループを決め直す。スニペットの一覧を出している間とストアを読めない時は出さない。
  ///
  /// スニペットグループはキー入力のたびにストアから読む (Mac と同じ。`documents/DIRECTION.md`「決めたこと」)。
  /// 入力欄の文字がメニューを閉じた時から変わったら、閉じた時の文字を捨てる。捨てないと、閉じた後に打ち直して同じ文字に戻った時もメニューを出さないため。
  private func refreshMatchedSnippetGroup() {
    guard !isShowingSnippets, case .success(let modelContainer) = keyboardModelContainerResult else {
      matchedSnippetGroup = nil
      return
    }
    let documentContextBeforeInput = textDocumentProxy.documentContextBeforeInput
    if documentContextBeforeInput != dismissedDocumentContextBeforeInput {
      dismissedDocumentContextBeforeInput = nil
    }
    matchedSnippetGroup = snippetGroupMatchingDocumentContext(
      documentContextBeforeInput: documentContextBeforeInput,
      dismissedDocumentContextBeforeInput: dismissedDocumentContextBeforeInput,
      snippetGroups: (try? modelContainer.mainContext.fetch(FetchDescriptor<SnippetGroup>())) ?? []
    )
  }

  /// キーで打った後に、メニューを出すスニペットグループを決め直す。
  ///
  /// 入力欄のアプリによっては `documentContextBeforeInput` が打った文字をすぐに含まないことがあるため、打った処理を終えてから読む。
  private func refreshMatchedSnippetGroupAfterKeyInput() {
    Task {
      refreshMatchedSnippetGroup()
    }
  }
}
