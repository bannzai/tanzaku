import AppKit
import Carbon.HIToolbox
import SwiftData
import SwiftUI
import TanzakuKit
import os

/// キー入力の監視のコールバックが呼ぶ controller。CGEventTap のコールバックは値を捕まえられない C の関数ポインタのため、ここに置いて参照する。
private var keyboardMonitoringSnippetGroupMenuController: SnippetGroupMenuController?

/// キー入力が作る文字 (`SnippetGroupMenuController` がキーワードの判定に使う)。CGEventTap のコールバック (MainActor の外) から呼ぶため nonisolated にする。
nonisolated private func keyboardEventCharacters(event: CGEvent) -> String {
  var characterCount = 0
  // キー入力 1 回が作る文字は通常 1〜2 (サロゲートペア) 個の UTF-16 のため、それより多めに取る。
  var utf16Characters = [UniChar](repeating: 0, count: 8)
  event.keyboardGetUnicodeString(maxStringLength: utf16Characters.count, actualStringLength: &characterCount, unicodeString: &utf16Characters)
  return String(utf16CodeUnits: utf16Characters, count: characterCount)
}

/// 今のキーボードの入力ソースが、キーの文字をそのまま入力欄に入れるもの (英字のキーボード配列・日本語入力の英数) か。取れなければ `false` にし、キーワードを判定しない側に倒す。
private func isKeyboardInputSourceASCIICapable() -> Bool {
  guard let inputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
    let isASCIICapable = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceIsASCIICapable)
  else {
    return false
  }
  return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(isASCIICapable).takeUnretainedValue())
}

/// スニペットとスニペットグループのキーワードの入力の監視・スニペットグループのメニューのパネル・本文の入力をまとめる。
///
/// スニペットのキーワードを打つとその場で本文に置き換え、スニペットグループのキーワードを打つとメニューを出す (`documents/DIRECTION.md`「決めたこと」)。
/// キー入力は CGEventTap で見る。メニューはフォーカスを奪わないパネルに出し、入力中のアプリを前面のまま残すため、メニューの ↑↓・Return・Esc はパネルではなく CGEventTap で受け取り、入力欄へ渡さない。
/// 打った文字はキーワードの判定だけに使い、保存・ログ出力・送信をしない (`documents/PROJECT.md`「スニペットグループとキーワード展開」、`.claude/rules/snippet-content-handling.md`)。
final class SnippetGroupMenuController {
  /// スニペットとスニペットグループを読むストア。
  let modelContainer: ModelContainer
  /// メニューの状態。
  private let state = SnippetGroupMenuState()
  /// メニューのパネル。初めて開く時に作る。
  private var panel: NSPanel?
  /// キー入力の監視。許可が無い時は `nil`。
  private var eventTap: CFMachPort?
  /// `eventTap` をメインスレッドの run loop につなぐ source。監視をやめる時に外す。
  private var eventTapRunLoopSource: CFRunLoopSource?
  /// キーワードの判定に使う、直前に打った文字 (`snippetGroupKeywordTypedText(typedText:keyCode:modifierFlags:characters:maxLength:)`)。
  private var typedText = ""
  /// 監視の失敗の記録。打った文字とスニペットの本文は入れない。
  private let logger = Logger(subsystem: "com.bannzai.tanzaku", category: "SnippetGroupMenu")

  /// ほかのアプリへ切り替えたら、直前に打った文字を捨ててメニューを閉じるよう、アプリの切り替えの通知を受け取り始める。
  init(modelContainer: ModelContainer) {
    self.modelContainer = modelContainer
    // 許可を与えた後にシステム設定から戻った時に監視を始めるためにも使う。
    _ = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) {
      [weak self] _ in
      MainActor.assumeIsolated {
        self?.handleApplicationActivation()
      }
    }
  }

  /// 許可がすべてあればキー入力の監視を始める。許可が無い・監視中なら何もしないため、何度呼んでも監視は 1 つになる。
  ///
  /// メニューの ↑↓・Return・Esc を入力欄へ渡さないため、イベントを書き換えられる `.defaultTap` にする (アクセシビリティの許可が要る)。
  func startKeyboardMonitoringIfAllowed() {
    guard eventTap == nil, isSnippetGroupKeywordExpansionAllowed() else {
      return
    }
    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: [CGEventType.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown].reduce(CGEventMask(0)) { eventMask, eventType in
          eventMask | (CGEventMask(1) << eventType.rawValue)
        },
        callback: { _, type, event, _ in
          // MainActor に渡す閉包に MainActor の外の `event` を持ち込まないよう、使う値を先に取り出す。
          let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
          let modifierFlags = event.flags
          let characters = type == .keyDown ? keyboardEventCharacters(event: event) : ""
          let sourceUserData = event.getIntegerValueField(.eventSourceUserData)
          // run loop の source をメインスレッドの run loop に足したため、コールバックはメインスレッドで呼ばれる。
          let isConsumed = MainActor.assumeIsolated {
            keyboardMonitoringSnippetGroupMenuController?.handleEvent(
              type: type,
              keyCode: keyCode,
              modifierFlags: modifierFlags,
              characters: characters,
              sourceUserData: sourceUserData
            ) ?? false
          }
          return isConsumed ? nil : Unmanaged.passUnretained(event)
        },
        userInfo: nil
      )
    else {
      logger.error("Failed to create the event tap for snippet groups")
      return
    }
    keyboardMonitoringSnippetGroupMenuController = self
    let eventTapRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)
    self.eventTap = eventTap
    self.eventTapRunLoopSource = eventTapRunLoopSource
  }

  /// キー入力の監視をやめてメニューを閉じる。監視していなければ何もしない。許可が取り消された時に使う。
  private func stopKeyboardMonitoring() {
    if let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      CFMachPortInvalidate(eventTap)
    }
    if let eventTapRunLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
    }
    eventTap = nil
    eventTapRunLoopSource = nil
    typedText = ""
    closeMenu()
  }

  /// メニューを開いているか。
  var isMenuOpen: Bool {
    state.snippetGroup != nil
  }

  /// `snippetGroup` のメニューを開く。パネルはキーワードの最後の文字が入力欄に入ってから、そのキャレットの位置に出す。
  func openMenu(snippetGroup: SnippetGroup) {
    state.snippetGroup = snippetGroup
    state.snippets = snippetGroupMenuSnippets(snippetGroup: snippetGroup)
    state.selectedSnippetIndex = 0
    // このメソッドはキーワードの最後の文字のキー入力を入力欄へ渡す前に呼ばれるため、そのキー入力を渡し終えてからキャレットの位置を取る。
    Task { [weak self] in
      self?.showPanel()
    }
  }

  /// メニューを閉じる。閉じていても何もしない。キーワードは入力欄に残る。
  func closeMenu() {
    panel?.orderOut(nil)
    state.snippetGroup = nil
    state.snippets = []
    state.selectedSnippetIndex = 0
  }

  /// 監視したイベントを処理する。メニューのキー操作か、スニペットのキーワードの最後の文字として受け取ったら `true` を返し、入力欄へ渡さない。
  private func handleEvent(type: CGEventType, keyCode: Int, modifierFlags: CGEventFlags, characters: String, sourceUserData: Int64) -> Bool {
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
      // 応答が遅れた・安全な入力 (パスワード欄) が続いた時にシステムが監視を止めるため、許可が残っていれば再開する。
      // 止まっている間の入力・クリックは見ていないため、打った文字とメニューは入力欄と合わなくなっている。再開の前に捨てる。
      typedText = ""
      closeMenu()
      if let eventTap, isSnippetGroupKeywordExpansionAllowed() {
        CGEvent.tapEnable(tap: eventTap, enable: true)
      } else {
        stopKeyboardMonitoring()
      }
      return false
    case .keyDown:
      // 本文を入れるために自分で送ったバックスペースと ⌘V。
      if sourceUserData == syntheticKeyEventUserData {
        return false
      }
      if isMenuOpen {
        if isSnippetGroupMenuKeyModifierFree(modifierFlags: modifierFlags), handleMenuKeyDown(keyCode: keyCode) {
          return true
        }
        // メニューの操作以外のキーは入力欄へ渡し、メニューは閉じる。キーワードの後に続けて打つ時にメニューを残さないため。
        closeMenu()
      }
      // このアプリの入力欄 (管理ウィンドウのキーワードの欄・ランチャーの検索欄) でキーワードを打った時にメニューを出さないため。
      if NSApp.isActive || NSApp.keyWindow != nil {
        typedText = ""
        return false
      }
      return updateTypedTextAndExpandKeyword(keyCode: keyCode, modifierFlags: modifierFlags, characters: characters)
    default:
      // マウスのクリックでキャレットが動き得るため、打った文字を捨てる。メニューはクリックで閉じる (パネルはクリックを受けない)。
      typedText = ""
      closeMenu()
      return false
    }
  }

  /// メニューを開いている間のキー操作。受け取ったら `true` を返す。
  private func handleMenuKeyDown(keyCode: Int) -> Bool {
    switch keyCode {
    case kVK_UpArrow, kVK_DownArrow:
      state.selectedSnippetIndex =
        launcherMovedSelectionIndex(
          currentIndex: state.selectedSnippetIndex,
          offset: keyCode == kVK_UpArrow ? -1 : 1,
          count: state.snippets.count
        ) ?? 0
      return true
    case kVK_Return, kVK_ANSI_KeypadEnter:
      insertSelectedSnippet()
      return true
    case kVK_Escape:
      // 閉じた直後のバックスペースで同じキーワードに戻った時に、閉じたメニューを出し直さないため。
      typedText = ""
      closeMenu()
      return true
    default:
      return false
    }
  }

  /// キー入力 1 回を受けてキーワードを判定する。スニペットを本文に置き換えた時だけ `true` を返し、呼び出し側はそのキー入力を入力欄へ渡さない。
  ///
  /// スニペットとスニペットグループはキー入力のたびにストアから読む。どちらも管理ウィンドウ・開発者メニュー・MCP・同期 (#19) のどこからでも変わり、読んだ結果を持つと変更の通知を漏れなく受け取る仕組みが要るため。キーワードを持つものだけを読むため、読む量はキーワードの数に比例する。
  private func updateTypedTextAndExpandKeyword(keyCode: Int, modifierFlags: CGEventFlags, characters: String) -> Bool {
    // 日本語などの入力ソースでは、キー入力の文字 (ローマ字) と入力欄に入る文字 (かな) が違い、変換の確定の Return をメニューの選択として奪い、消すバックスペースの数もずれるため判定しない。
    guard isKeyboardInputSourceASCIICapable() else {
      typedText = ""
      return false
    }
    let snippets: [Snippet]
    let snippetGroups: [SnippetGroup]
    do {
      snippets = try modelContainer.mainContext.fetch(FetchDescriptor<Snippet>(predicate: #Predicate { $0.keyword != nil }))
      snippetGroups = try modelContainer.mainContext.fetch(FetchDescriptor<SnippetGroup>(predicate: #Predicate { $0.keyword != nil }))
    } catch {
      logger.error("Failed to fetch snippets and snippet groups: \(String(describing: error), privacy: .public)")
      typedText = ""
      return false
    }
    // キーワードを持つスニペットもグループも無ければ照合するものが無いため、打った文字を持たない (長さ 0)。キーワードは読む時の条件で `nil` を除いてある。
    typedText = snippetGroupKeywordTypedText(
      typedText: typedText,
      keyCode: keyCode,
      modifierFlags: modifierFlags,
      characters: characters,
      maxLength: (snippets.map { ($0.keyword ?? "").count } + snippetGroups.map { ($0.keyword ?? "").count }).max() ?? 0
    )
    if let snippet = snippetMatchingTypedText(typedText: typedText, snippets: snippets, snippetGroups: snippetGroups), let keyword = snippet.keyword {
      // バックスペースで末尾がスニペットのキーワードに戻った時は、置き換えもグループのメニューも起こさない (最後の文字を打ち直すと置き換わる)。
      guard isSnippetKeywordExpansionKey(keyCode: keyCode) else {
        return false
      }
      // 置き換えた直後のバックスペースで同じキーワードに戻った時に、もう一度置き換えないため。
      typedText = ""
      insertSnippet(snippet: snippet, backspaceCount: snippetKeywordBackspaceCount(keyword: keyword))
      return true
    }
    // 打った文字は開いた後も残す。短いキーワード (`;dev`) のメニューを出した後に長いキーワード (`;dev-env`) を打ち続けた時に、長い方のメニューを出すため。
    if let snippetGroup = snippetGroupMatchingTypedText(typedText: typedText, snippetGroups: snippetGroups) {
      openMenu(snippetGroup: snippetGroup)
    }
    return false
  }

  /// メニューで選んでいるスニペットを入れる。打ったキーワードは入力欄にすべて入っているため、キーワードの文字数だけ消す。
  ///
  /// 冪等ではない: 呼ぶたびに入力が 1 回起きる。
  private func insertSelectedSnippet() {
    guard state.snippets.indices.contains(state.selectedSnippetIndex), let keyword = state.snippetGroup?.keyword else {
      closeMenu()
      return
    }
    // closeMenu() がメニューのスニペットを空にするため、閉じる前に取っておく。
    let snippet = state.snippets[state.selectedSnippetIndex]
    closeMenu()
    typedText = ""
    insertSnippet(snippet: snippet, backspaceCount: snippetGroupKeywordBackspaceCount(keyword: keyword))
  }

  /// 打ったキーワードをバックスペース `backspaceCount` 回で消し、`snippet` の本文をクリップボードに入れて ⌘V で貼り付ける。
  ///
  /// 本文を文字のキー入力として送らず貼り付けるのは、改行を Return として受け取って送信するアプリ (チャットなど) で本文の途中で送信されないため (`documents/DIRECTION.md`「決めたこと」)。
  /// 入れた後に使った日時を記録する。保存に失敗しても記録だけにする。本文は入っており、ランチャーの最近使ったスニペットに出ないだけのため。
  /// 冪等ではない: 呼ぶたびに入力が 1 回起きる。
  private func insertSnippet(snippet: Snippet, backspaceCount: Int) {
    for _ in 0..<backspaceCount {
      postSyntheticKeyStroke(virtualKey: kVK_Delete, flags: [])
    }
    copySnippetBodyToPasteboard(body: snippet.body)
    postSyntheticKeyStroke(virtualKey: kVK_ANSI_V, flags: .maskCommand)
    do {
      try recordSnippetUse(snippet: snippet, usedAt: .now, modelContext: modelContainer.mainContext)
    } catch {
      logger.error("Failed to record the snippet use: \(String(describing: error))")
    }
  }

  /// ほかのアプリへ切り替えた時の処理。打った文字は切り替える前の入力欄のものなので捨て、メニューを閉じる。許可を与えて戻ってきた時に備えて監視を始め直す。
  private func handleApplicationActivation() {
    typedText = ""
    closeMenu()
    startKeyboardMonitoringIfAllowed()
  }

  /// メニューのパネルを入力欄のキャレットの位置 (取れなければマウスポインタの位置) に出す。出す前にメニューを閉じていれば何もしない。
  private func showPanel() {
    guard isMenuOpen else {
      return
    }
    let panel = panel ?? makePanel()
    self.panel = panel
    let menuSize = snippetGroupMenuSize(snippetCount: state.snippets.count)
    let mouseLocation = NSEvent.mouseLocation
    let caretRect = focusedTextCaretRect()
    // Quartz の座標の原点は主画面 (メニューバーのある画面。`NSScreen.screens` の先頭) の左上。画面が無い時は位置を決められないため 0 にし、`visibleFrame` の中に収める処理に任せる。
    let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
    panel.setFrame(
      NSRect(
        origin: snippetGroupMenuOrigin(
          caretRect: caretRect,
          mouseLocation: mouseLocation,
          menuSize: menuSize,
          primaryScreenHeight: primaryScreenHeight,
          visibleFrame: screenVisibleFrame(location: caretRect.map { CGPoint(x: $0.minX, y: primaryScreenHeight - $0.maxY) } ?? mouseLocation)
        ),
        size: menuSize
      ),
      display: true
    )
    // このアプリを前面にしないまま出すため、キーウィンドウにせず前に出すだけにする。
    panel.orderFrontRegardless()
  }

  /// `location` (AppKit の座標) を含む画面の、Dock・メニューバーを除いた範囲。どの画面にも無ければ主に使っている画面、画面が無ければ大きさ 0 の範囲。
  private func screenVisibleFrame(location: CGPoint) -> CGRect {
    (NSScreen.screens.first { $0.frame.contains(location) } ?? NSScreen.main)?.visibleFrame ?? .zero
  }

  /// メニューのパネルを作る。角丸と縁は SwiftUI で描くため、ウィンドウは枠なし・透明にする。
  private func makePanel() -> NSPanel {
    // 枠なしのパネルはキーウィンドウにならないため、入力中のアプリのキーウィンドウとフォーカスはそのまま残る。
    let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    panel.isFloatingPanel = true
    // 入力中のアプリのフローティングウィンドウより前に出すため、メニューと同じ階層にする。
    panel.level = .popUpMenu
    // このアプリは前面にならないため、アプリが前面でない時に隠す既定の動きを止める。
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    // クリックは下のアプリへ通し、メニューは CGEventTap で受けたクリックで閉じる。
    panel.ignoresMouseEvents = true
    panel.setAccessibilityIdentifier("snippetGroupMenuPanel")
    panel.contentView = NSHostingView(rootView: SnippetGroupMenuView(state: state))
    return panel
  }
}
