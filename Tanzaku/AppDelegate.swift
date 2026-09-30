import AppKit
import SwiftData
import TanzakuKit
import os

/// アプリの起動時にストア・ランチャー・グローバルショートカット・意味検索の埋め込みモデルを用意する。SwiftUI の `App` には起動の完了を受け取る場所が無いため、`NSApplicationDelegate` で受け取る。
final class AppDelegate: NSObject, NSApplicationDelegate {
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
  /// 起動時の準備の失敗の記録。
  private let logger = Logger(subsystem: "com.bannzai.tanzaku", category: "AppDelegate")

  /// ストアを開いてランチャーを作り、ショートカットを登録し、意味検索の埋め込みモデルの用意を始める。
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
    do {
      try registerGlobalHotKey(keyCode: launcherHotKeyCode, modifiers: launcherHotKeyModifiers) {
        launcherPanelController.toggle()
      }
    } catch {
      logger.error("Failed to register the launcher shortcut: \(String(describing: error), privacy: .public)")
    }
    Task {
      await launcherPanelController.loadSnippetEmbeddingModel()
    }
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
