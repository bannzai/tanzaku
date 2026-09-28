import SwiftData
import SwiftUI

/// アプリのエントリポイント。
@main
struct TanzakuApp: App {
  /// アプリ全体で使うストア。作れなかった時はウィンドウにエラーを出す (アプリを落とすと理由をユーザーが知れないため)。
  private let modelContainerResult = Result { try makeMacModelContainer() }

  var body: some Scene {
    WindowGroup {
      switch modelContainerResult {
      case .success(let modelContainer):
        ManagerView()
          .modelContainer(modelContainer)
      case .failure(let error):
        Text(error.localizedDescription)
          .frame(minWidth: 480, minHeight: 320)
      }
    }
    // デザインの管理ウィンドウの大きさ (`documents/design/Manager.dc.html` の 1280×800)。
    .defaultSize(width: 1280, height: 800)
    .commands {
      // 管理ウィンドウは 1 つで足りるため「新規ウインドウ」を外し、⌘N を新規スニペット (`ManagerView` のツールバー) に使う。閉じたウインドウは Dock のアイコンで開き直せる。
      CommandGroup(replacing: .newItem) {}
      #if DEBUG
        if case .success(let modelContainer) = modelContainerResult {
          DebugCommands(modelContainer: modelContainer)
        }
      #endif
    }
  }
}
