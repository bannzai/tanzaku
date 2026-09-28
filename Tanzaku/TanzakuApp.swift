import SwiftUI

/// 管理ウィンドウの scene の識別子。ランチャーから `openWindow(id:)` で開くのに使う。
let managerWindowID = "manager"

/// アプリのエントリポイント。
@main
struct TanzakuApp: App {
  /// ストア・ランチャー・グローバルショートカットを用意する delegate。
  @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

  var body: some Scene {
    // ランチャーから開いた時に既に開いている管理ウィンドウを前に出すため、複数のウィンドウを作る WindowGroup ではなく 1 つだけの Window にする。
    Window("Tanzaku", id: managerWindowID) {
      ManagerWindowRoot(appDelegate: appDelegate)
    }
    #if DEBUG
      .commands {
        DeveloperCommands(appDelegate: appDelegate)
      }
    #endif
  }
}

/// 管理ウィンドウの中身を包み、ランチャーから管理ウィンドウを開けるよう `openWindow` を delegate に渡す。
private struct ManagerWindowRoot: View {
  /// `openWindow` と新規作成の下書きを受け渡す delegate。
  let appDelegate: AppDelegate
  /// 管理ウィンドウを開く SwiftUI の操作。
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    ContentView()
      .environment(appDelegate.newSnippetDraft)
      .onAppear {
        appDelegate.openManagerWindow = {
          openWindow(id: managerWindowID)
        }
      }
  }
}
