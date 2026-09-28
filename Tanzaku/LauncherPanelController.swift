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
  /// 意味検索の埋め込みモデル。埋め込みモデルの資産のダウンロードが済むまでは `nil` で、その間は文字列の一致だけで検索する。
  ///
  /// 用意できた時にランチャーが開いていても意味検索の結果が出るよう、入った時にベクトルを作って検索し直す。
  var snippetTextEmbedder: SnippetTextEmbedder? {
    didSet {
      refreshSnippetEmbeddingsAndSearch()
    }
  }
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

  /// 入力と結果を空にしてパネルを画面の中央に開く。
  func show() {
    let frontmostApplication = NSWorkspace.shared.frontmostApplication
    previousApplication = frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmostApplication
    state.query = ""
    state.searchResult = SnippetSearchResult(keywordMatches: [], semanticMatches: [])
    state.selectedSnippetIndex = nil
    state.presentationCount += 1
    let panel = panel ?? makePanel()
    self.panel = panel
    if let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
      panel.setFrameOrigin(NSPoint(x: visibleFrame.midX - panel.frame.width / 2, y: visibleFrame.midY - panel.frame.height / 2))
    }
    panel.makeKeyAndOrderFront(nil)
    // ベクトルの作成はパネルを描いた後に回し、ショートカットを押してからパネルが出るまでを待たせない。
    DispatchQueue.main.async { [weak self] in
      self?.refreshSnippetEmbeddingsAndSearch()
    }
  }

  /// パネルを閉じる。閉じていれば何もしない。
  func close() {
    panel?.orderOut(nil)
  }

  /// パネルがキーウィンドウでなくなった (ほかのウィンドウをクリックした) ら閉じる。Spotlight と同じく、ランチャーを使い終えたら残さないため。
  func windowDidResignKey(_ notification: Notification) {
    close()
  }

  /// 検索して結果を入れ替え、先頭を選ぶ。
  private func search() {
    do {
      state.searchResult = try searchSnippets(query: state.query, modelContext: modelContainer.mainContext, embedder: snippetTextEmbedder)
    } catch {
      logger.error("Failed to search snippets: \(String(describing: error))")
      state.searchResult = SnippetSearchResult(keywordMatches: [], semanticMatches: [])
    }
    state.selectedSnippetIndex = launcherMovedSelectionIndex(
      currentIndex: nil,
      offset: 0,
      count: launcherSelectableSnippets(searchResult: state.searchResult).count
    )
  }

  /// 意味検索のベクトルを今のスニペットに合わせ、パネルが開いていれば今の入力で検索し直す。管理ウィンドウ・MCP で変わったスニペットを、開くたびに意味検索へ反映するため。
  ///
  /// 変わっていないベクトルは作り直さないため、推論が走るのは追加・更新されたスニペットだけになる。推論はメインスレッドで行う: 埋め込みモデルは NLContextualEmbedding を捕まえた Sendable でない閉包で、別のスレッドへ渡せないため。
  private func refreshSnippetEmbeddingsAndSearch() {
    guard let snippetTextEmbedder else {
      return
    }
    do {
      try updateSnippetEmbeddings(modelContext: modelContainer.mainContext, embedder: snippetTextEmbedder)
      try modelContainer.mainContext.save()
    } catch {
      logger.error("Failed to update snippet embeddings: \(String(describing: error))")
    }
    if panel?.isVisible == true {
      search()
    }
  }

  /// パネルのキー操作を処理する。処理したら `true` を返し、キーを検索欄へ渡さない。
  ///
  /// 日本語の入力の変換中 (未確定の文字がある時) の Return・Esc・↑↓ は変換の確定・取り消し・候補の選択に使うため、処理せず検索欄へ渡す。
  private func handleKeyDown(event: NSEvent, panel: LauncherPanel) -> Bool {
    if (panel.firstResponder as? NSTextView)?.hasMarkedText() == true {
      return false
    }
    let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
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
    guard launcherContentState(query: state.query, searchResult: state.searchResult) == .empty else {
      return
    }
    close()
    openNewSnippetEditor(state.query.trimmingCharacters(in: .whitespacesAndNewlines))
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
          self?.search()
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
