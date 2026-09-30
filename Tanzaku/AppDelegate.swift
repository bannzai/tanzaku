import AppKit
import SwiftData
import SwiftUI
import TanzakuKit
import os

/// アプリの起動時にストア・ランチャー・グローバルショートカット・意味検索の埋め込みモデルを用意する。SwiftUI の `App` には起動の完了を受け取る場所が無いため、`NSApplicationDelegate` で受け取る。
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  /// ランチャーから新規作成に進んだ時の下書き。管理ウィンドウが読む。
  let newSnippetDraft = NewSnippetDraft()
  /// ランチャーと管理ウィンドウが共有するストア。
  ///
  /// 管理ウィンドウの scene の中身が `applicationDidFinishLaunching` より先に作られても同じストアを渡せるよう、起動の完了を待たずに delegate を作る時に開く。
  let modelContainerResult = Result { try makeMacModelContainer() }
  /// 意味検索のベクトルを作り直した回数。管理ウィンドウが読む。
  let snippetEmbeddingRevision = SnippetEmbeddingRevision()
  /// 管理ウィンドウを開く。SwiftUI の `openWindow` はビューの中でしか取れないため、管理ウィンドウのビューが表示された時に入れる。
  var openManagerWindow: (() -> Void)?
  /// ランチャー。ストアを開けなかった時は `nil` で、ランチャーは開かない。
  private(set) var launcherPanelController: LauncherPanelController?
  /// 内蔵の MCP のサーバー。ストアを開けなかった時は `nil` で、サーバーは起動しない。
  ///
  /// 設定のウィンドウの scene が `applicationDidFinishLaunching` より先に読んでも同じものを渡せるよう、最初に読まれた時に作る (作るとサーバーが起動する)。
  /// 意味検索はランチャーと同じ埋め込みモデルを使う。ランチャーを作る前に届いた検索は意味検索なしになる。
  private(set) lazy var mcpServerController: MCPServerController? = (try? modelContainerResult.get()).map { modelContainer in
    MCPServerController(
      modelContainer: modelContainer,
      tokenStore: keychainMCPTokenStore(),
      semanticQueryEmbedder: { [weak self] query in
        await self?.launcherPanelController?.semanticQueryEmbedder(query: query)
      },
      snippetsDidChange: { [weak self] in
        self?.launcherPanelController?.refreshSnippetEmbeddingsAndSearch()
      }
    )
  }
  /// ランチャーのショートカット。設定の「一般」と初回起動が変える。
  let launcherShortcutController = LauncherShortcutController(userDefaults: .standard)
  /// 初回起動のウィンドウ。出していない時は `nil`。
  private var onboardingWindow: NSWindow?
  /// 起動時の準備の失敗の記録。
  private let logger = Logger(subsystem: "com.bannzai.tanzaku", category: "AppDelegate")

  /// ストアを開いてランチャーを作り、ショートカットを登録し、意味検索の埋め込みモデルの用意を始める。初回起動を終えていなければ初回起動のウィンドウを出す。
  ///
  /// 失敗しても落とさず記録だけにする。ユニットテストはこのアプリを起動して走るため、落とすとテストが走らない。
  func applicationDidFinishLaunching(_ notification: Notification) {
    let launcherPanelController: LauncherPanelController
    do {
      launcherPanelController = LauncherPanelController(modelContainer: try modelContainerResult.get()) { [weak self] draftTitle in
        self?.openNewSnippetEditor(draftTitle: draftTitle)
      }
    } catch {
      logger.error("Failed to open the store: \(String(describing: error))")
      return
    }
    launcherPanelController.onSnippetEmbeddingsUpdate = { [weak self] in
      self?.snippetEmbeddingRevision.value += 1
    }
    self.launcherPanelController = launcherPanelController
    // 設定のウィンドウを開かなくても AI エージェントが接続できるよう、起動時にサーバーを起動する (`documents/DIRECTION.md`「決めたこと」)。
    _ = mcpServerController
    launcherShortcutController.start {
      launcherPanelController.toggle()
    }
    if let errorMessage = launcherShortcutController.errorMessage {
      logger.error("Failed to register the launcher shortcut: \(errorMessage, privacy: .public)")
    }
    Task {
      await launcherPanelController.loadSnippetEmbeddingModel()
    }
    if !isOnboardingCompleted(userDefaults: .standard) {
      showOnboardingWindow()
    }
  }

  /// 初回起動のウィンドウを出す。出していれば前に出すだけで、2 つ目は作らない。ストアを開けなかった時は出さない。
  ///
  /// 管理ウィンドウ (SwiftUI の `Window`) は起動時に開くため、初回起動はその上に重ねる別のウィンドウにする。Debug ビルドの開発者メニューも初回起動を撮り直すのに呼ぶため private にしない。
  func showOnboardingWindow() {
    guard let modelContainer = try? modelContainerResult.get(), let mcpServerController else {
      return
    }
    let window =
      onboardingWindow
      ?? {
        let window = NSWindow(
          contentViewController: NSHostingController(
            rootView: OnboardingView(
              onSnippetsChange: { [weak self] in
                self?.launcherPanelController?.refreshSnippetEmbeddingsAndSearch()
              },
              onFinish: { [weak self] in
                self?.onboardingWindow?.close()
              }
            )
            .modelContainer(modelContainer)
            .environment(mcpServerController)
            .environment(launcherShortcutController)
          )
        )
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setAccessibilityIdentifier("onboardingWindow")
        window.center()
        onboardingWindow = window
        return window
      }()
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
  }

  /// 初回起動のウィンドウを閉じたら、初回起動を終えたことにする。
  ///
  /// 「はじめる」だけでなく閉じるボタンで閉じた時も終えたことにする。常駐するアプリで、閉じたウィンドウを起動のたびに出し直すと邪魔になり、手順の内容は設定からいつでも変えられるため。
  func windowWillClose(_ notification: Notification) {
    guard (notification.object as? NSWindow) === onboardingWindow else {
      return
    }
    markOnboardingCompleted(userDefaults: .standard)
    onboardingWindow = nil
  }

  /// 管理ウィンドウを閉じてもアプリを終了させない。ランチャーはグローバルショートカットでいつでも開くため常駐する必要があり、1 つだけの `Window` の scene は閉じるとアプリを終了させるため。
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  /// 入力した言葉を下書きにして、アプリを前面に出して管理ウィンドウを開く。
  private func openNewSnippetEditor(draftTitle: String) {
    newSnippetDraft.title = draftTitle
    NSApp.activate()
    openManagerWindow?()
  }
}
