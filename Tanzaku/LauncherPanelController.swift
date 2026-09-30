import AppKit
import Carbon.HIToolbox
import SwiftData
import SwiftUI
import TanzakuKit
import os

/// ランチャーを出すパネル。枠なしのパネルは既定ではキーウィンドウになれず検索欄に入力できないため、なれるようにする。
final class LauncherPanel: NSPanel {
  override var canBecomeKey: Bool {
    true
  }
}

/// ランチャーのパネルの表示・検索・キー操作・選んだスニペットの出力をまとめる。
///
/// パネルは `nonactivatingPanel` にし、開いてもこのアプリを前面にしない。ランチャーを開く前に使っていたアプリを前面のまま残し、⌘Return の貼り付け先にするため。
final class LauncherPanelController: NSObject, NSWindowDelegate {
  /// スニペットを検索するストア。Debug ビルドの開発者メニュー (`DeveloperCommands`) がスニペットを入れる・消すのにも使うため private にしない。
  let modelContainer: ModelContainer
  /// 結果なしの画面から新規作成に進んだ時に、入力した言葉を渡して管理ウィンドウの編集を開く。
  private let openNewSnippetEditor: (String) -> Void
  /// 意味検索のベクトルを作る actor。`loadSnippetEmbeddingModel()` で埋め込みモデルを用意できるまでは `nil` で、その間は文字列の一致だけで検索する。
  private var snippetEmbeddingIndexer: SnippetEmbeddingIndexer?
  /// 用意できた埋め込みモデルの `modelIdentifier`。検索の入力のベクトルを作ったモデルと、保存したベクトルのモデルを揃えるのに使う。
  private var snippetEmbeddingModelIdentifier: String?
  /// 実行中の意味検索。入力が変わったら古い入力の意味検索を取り消す。
  private var semanticSearchTask: Task<Void, Never>?
  /// 画面の状態。
  private let state = LauncherState()
  /// ランチャーのパネル。初めて開く時に作る。
  private var panel: LauncherPanel?
  /// ランチャーを開く前に前面にあったアプリ。⌘Return の貼り付け先。
  private var previousApplication: NSRunningApplication?
  /// ランチャーのエラーの記録。スニペットの本文は入れない (`.claude/rules/snippet-content-handling.md`)。
  private let logger = Logger(subsystem: "com.bannzai.tanzaku", category: "Launcher")

  /// `openNewSnippetEditor` は結果なしの画面から新規作成に進んだ時に呼ぶ。パネルのキー操作をアプリのキー入力の監視で受け取るため、ここで監視を始める。
  init(modelContainer: ModelContainer, openNewSnippetEditor: @escaping (String) -> Void) {
    self.modelContainer = modelContainer
    self.openNewSnippetEditor = openNewSnippetEditor
    super.init()
    // 検索欄の入力中も ↑↓・Return・Esc・⌘N を受け取るため、検索欄 (フィールドエディタ) より前にアプリのキー入力の監視で受け取る。
    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, let panel = self.panel, event.window === panel else {
        return event
      }
      return self.handleKeyDown(event: event, panel: panel) ? nil : event
    }
  }

  /// 閉じていれば開き、開いていれば閉じる。グローバルショートカットで呼ぶ。
  func toggle() {
    if panel?.isVisible == true {
      close()
    } else {
      show()
    }
  }

  /// パネルを画面の中央に開く。入力と結果は閉じた時に空にしてある。
  func show() {
    let frontmostApplication = NSWorkspace.shared.frontmostApplication
    previousApplication = frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmostApplication
    state.presentationCount += 1
    let panel = panel ?? makePanel()
    self.panel = panel
    if let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
      panel.setFrameOrigin(NSPoint(x: visibleFrame.midX - panel.frame.width / 2, y: visibleFrame.midY - panel.frame.height / 2))
    }
    panel.makeKeyAndOrderFront(nil)
    refreshSnippetEmbeddingsAndSearch()
  }

  /// 意味検索の埋め込みモデルを用意する。用意できたらベクトルを作り、ランチャーが開いていれば今の入力で検索し直す。アプリの起動時に 1 回呼ぶ。
  func loadSnippetEmbeddingModel() async {
    // @ModelActor の actor はメインスレッドで作ると ModelContext の処理がメインスレッドで動くと報告されている (このアプリでは確かめていない) ため、確実にメインスレッドの外で作る。
    let snippetEmbeddingIndexer = await Task.detached { [modelContainer] in
      SnippetEmbeddingIndexer(modelContainer: modelContainer)
    }.value
    do {
      guard let modelIdentifier = try await snippetEmbeddingIndexer.loadSnippetTextEmbedder(preferredLanguages: Locale.preferredLanguages) else {
        return
      }
      self.snippetEmbeddingIndexer = snippetEmbeddingIndexer
      snippetEmbeddingModelIdentifier = modelIdentifier
      refreshSnippetEmbeddingsAndSearch()
    } catch {
      logger.error("Failed to load the embedding model: \(String(describing: error), privacy: .public)")
    }
  }

  /// パネルを閉じ、入力と結果を空にする。閉じていても空にするだけで、何度呼んでも同じ状態になる。
  ///
  /// 閉じたパネルの画面は残るため、結果のスニペットを持ったままにしない。管理ウィンドウ・MCP・開発者メニューがそのスニペットを消した後に、閉じた画面が消えたスニペットを読み直さないようにするため。
  /// simtunnel で、結果を出したまま閉じた後に開発者メニューの「Delete All Snippets」を押すと、削除は保存されたうえでアプリが落ちた。落ちた箇所のログは取れておらず、原因がこの読み直しだというのは推定。
  func close() {
    panel?.orderOut(nil)
    semanticSearchTask?.cancel()
    state.query = ""
    state.searchResult = SnippetSearchResult(keywordMatches: [], semanticMatches: [])
    state.isSemanticSearchPending = false
    state.selectedSnippetIndex = nil
  }

  /// パネルがキーウィンドウでなくなった (ほかのウィンドウをクリックした) ら閉じる。Spotlight と同じく、ランチャーを使い終えたら残さないため。
  func windowDidResignKey(_ notification: Notification) {
    close()
  }

  /// 今の入力で検索して結果を入れ替える。
  ///
  /// 文字列の一致はすぐに出し、意味検索は入力のベクトルを `SnippetEmbeddingIndexer` で作ってから足す。入力のベクトルの推論でキー入力を止めないため。
  /// `keepsSelection` が `false` (入力が変わった) なら先頭を選ぶ。`true` (入力を変えずにベクトルを作り直した) なら選んでいたスニペットを選び続け、意味検索の結果が届くまで文字列の一致だけの結果に入れ替えない (選んでいた意味検索の結果が一度消えて選択が移らないようにするため)。
  private func search(keepsSelection: Bool) {
    let query = state.query
    semanticSearchTask?.cancel()
    guard let snippetEmbeddingIndexer, let snippetEmbeddingModelIdentifier else {
      state.isSemanticSearchPending = false
      applySearchResult(query: query, embedder: nil, selectedSnippetID: keepsSelection ? selectedSnippetID() : nil)
      return
    }
    state.isSemanticSearchPending = true
    if !keepsSelection {
      applySearchResult(query: query, embedder: nil, selectedSnippetID: nil)
    }
    semanticSearchTask = Task { [weak self] in
      let queryVector: [Float]?
      do {
        queryVector = try await snippetEmbeddingIndexer.queryVector(query: query)
      } catch is CancellationError {
        return
      } catch {
        self?.logger.error("Failed to embed the query: \(String(describing: error))")
        queryVector = nil
      }
      // 入力が変わって取り消された検索は、新しい入力の検索が待ちの状態を持つため、何もしない。
      guard !Task.isCancelled, let self, self.state.query == query else {
        return
      }
      self.state.isSemanticSearchPending = false
      if let queryVector {
        // 入力のベクトルは作り終えているため、検索にはそれを返すだけの埋め込みモデルを渡す。
        self.applySearchResult(
          query: query,
          embedder: SnippetTextEmbedder(modelIdentifier: snippetEmbeddingModelIdentifier) { _ in queryVector },
          selectedSnippetID: self.selectedSnippetID()
        )
      }
    }
  }

  /// 検索の結果を入れ替え、`selectedSnippetID` のスニペットが新しい結果にあれば選び続け、無ければ先頭を選ぶ。
  private func applySearchResult(query: String, embedder: SnippetTextEmbedder?, selectedSnippetID: UUID?) {
    do {
      state.searchResult = try searchSnippets(query: query, modelContext: modelContainer.mainContext, embedder: embedder)
    } catch {
      logger.error("Failed to search snippets: \(String(describing: error))")
      state.searchResult = SnippetSearchResult(keywordMatches: [], semanticMatches: [])
    }
    state.selectedSnippetIndex = launcherSelectionIndexAfterResultUpdate(searchResult: state.searchResult, selectedSnippetID: selectedSnippetID)
  }

  /// 今選んでいるスニペットの `id`。
  private func selectedSnippetID() -> UUID? {
    launcherSelectedSnippet(searchResult: state.searchResult, selectedSnippetIndex: state.selectedSnippetIndex)?.id
  }

  /// 意味検索のベクトルを今のスニペットに合わせ、パネルが開いていれば今の入力で検索し直す。管理ウィンドウ・MCP で変わったスニペットを、開くたびに意味検索へ反映するため。
  ///
  /// ベクトルは `SnippetEmbeddingIndexer` がメインスレッドの外で作る。変わっていないベクトルは作り直さないため、推論が走るのは追加・更新されたスニペットだけになる。
  private func refreshSnippetEmbeddingsAndSearch() {
    guard let snippetEmbeddingIndexer else {
      return
    }
    Task { [weak self] in
      do {
        try await snippetEmbeddingIndexer.updateEmbeddings()
      } catch {
        self?.logger.error("Failed to update snippet embeddings: \(String(describing: error))")
      }
      if self?.panel?.isVisible == true {
        self?.search(keepsSelection: true)
      }
    }
  }

  /// パネルのキー操作を処理する。処理したら `true` を返し、キーを検索欄へ渡さない。
  ///
  /// 日本語の入力の変換中 (未確定の文字がある時) の Return・Esc・↑↓ は変換の確定・取り消し・候補の選択に使うため、処理せず検索欄へ渡す。
  private func handleKeyDown(event: NSEvent, panel: LauncherPanel) -> Bool {
    if (panel.firstResponder as? NSTextView)?.hasMarkedText() == true {
      return false
    }
    // Caps Lock と Fn は押しているかに関係なく立つため、ショートカットの判定に使う修飾キーだけを見る。
    let modifierFlags = event.modifierFlags.intersection([.command, .option, .control, .shift])
    switch Int(event.keyCode) {
    case kVK_Escape:
      close()
      return true
    case kVK_UpArrow, kVK_DownArrow:
      state.selectedSnippetIndex = launcherMovedSelectionIndex(
        currentIndex: state.selectedSnippetIndex,
        offset: Int(event.keyCode) == kVK_UpArrow ? -1 : 1,
        count: launcherSelectableSnippets(searchResult: state.searchResult).count
      )
      return true
    case kVK_Return, kVK_ANSI_KeypadEnter:
      outputSelectedSnippet(
        action: modifierFlags.contains(.command)
          ? launcherCommandReturnAction(
            isDirectPasteEnabled: UserDefaults.standard.bool(forKey: directPasteEnabledUserDefaultsKey),
            isAccessibilityTrusted: isAccessibilityTrusted()
          )
          : .copy
      )
      return true
    case kVK_ANSI_N where modifierFlags == .command:
      createSnippetFromQuery()
      return true
    default:
      return false
    }
  }

  /// 選んでいるスニペットをコピー (と貼り付け) してパネルを閉じる。選んでいなければ何もしない。
  private func outputSelectedSnippet(action: LauncherOutputAction) {
    guard let snippet = launcherSelectedSnippet(searchResult: state.searchResult, selectedSnippetIndex: state.selectedSnippetIndex) else {
      return
    }
    copySnippetBodyToPasteboard(body: snippet.body)
    close()
    if action == .copyAndPaste {
      pasteToApplication(application: previousApplication)
    }
  }

  /// 結果なしの時だけ、入力した言葉を下書きにして管理ウィンドウの編集を開く (`documents/design/LauncherEmpty.dc.html`)。
  private func createSnippetFromQuery() {
    guard launcherContentState(query: state.query, searchResult: state.searchResult, isSemanticSearchPending: state.isSemanticSearchPending) == .empty else {
      return
    }
    // close() が入力を空にするため、閉じる前に下書きのタイトルを取っておく。
    let draftTitle = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
    close()
    openNewSnippetEditor(draftTitle)
  }

  /// ランチャーのパネルを作る。デザインのパネル (720 x 480) の角丸と縁は SwiftUI で描くため、ウィンドウは枠なし・透明にする。
  private func makePanel() -> LauncherPanel {
    let panel = LauncherPanel(
      contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: true
    )
    panel.isFloatingPanel = true
    panel.level = .floating
    // このアプリは前面にならないため、アプリが前面でない時に隠す既定の動きを止める。
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.delegate = self
    panel.setAccessibilityIdentifier("launcherPanel")
    panel.contentView = NSHostingView(
      rootView: LauncherView(
        state: state,
        onQueryChange: { [weak self] in
          self?.search(keepsSelection: false)
        },
        onCopySelectedSnippet: { [weak self] in
          self?.outputSelectedSnippet(action: .copy)
        },
        onCreateSnippet: { [weak self] in
          self?.createSnippetFromQuery()
        }
      )
    )
    return panel
  }
}
