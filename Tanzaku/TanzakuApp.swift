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
    // デザインの管理ウィンドウの大きさ (`documents/design/Manager.dc.html` の 1280×800)。
    .defaultSize(width: 1280, height: 800)
    .commands {
      HelpCommands()
      #if DEBUG
        DeveloperCommands(appDelegate: appDelegate)
      #endif
    }

    Settings {
      SettingsRoot(appDelegate: appDelegate)
    }
  }
}

/// 設定のウィンドウの中身。タブはデザイン (`documents/design/Settings.dc.html`) の「一般」と「AI エージェント」。
private struct SettingsRoot: View {
  /// ストア・MCP のサーバー・ランチャーのショートカットを持つ delegate。
  let appDelegate: AppDelegate

  var body: some View {
    Group {
      switch (appDelegate.modelContainerResult, appDelegate.mcpServerController) {
      case (.success(let modelContainer), .some(let mcpServerController)):
        TabView {
          GeneralSettingsView()
            .tabItem {
              Label("General", systemImage: "gearshape")
            }
          AgentSettingsView()
            .tabItem {
              Label("AI Agents", systemImage: "cpu")
            }
        }
        .modelContainer(modelContainer)
        .environment(mcpServerController)
        .environment(appDelegate.launcherShortcutController)
      case (.failure(let error), _):
        // ストアを開けなかった理由をユーザーが知れるよう、管理ウィンドウと同じくアプリを落とさずに出す。
        Text(verbatim: error.localizedDescription)
      case (.success, .none):
        // ストアを開けた時は MCP のサーバーも作るため (`AppDelegate.mcpServerController`)、ここには来ない。
        EmptyView()
      }
    }
    .frame(width: 600)
    .frame(minHeight: 640)
  }
}

/// 管理ウィンドウの中身を包み、ランチャーから管理ウィンドウを開けるよう `openWindow` を delegate に渡す。
private struct ManagerWindowRoot: View {
  /// ストア・`openWindow`・新規作成の下書きを受け渡す delegate。
  let appDelegate: AppDelegate
  /// 管理ウィンドウを開く SwiftUI の操作。
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Group {
      switch appDelegate.modelContainerResult {
      case .success(let modelContainer):
        ManagerView(
          semanticQueryEmbedder: { query in
            await appDelegate.launcherPanelController?.semanticQueryEmbedder(query: query)
          },
          onSnippetsChange: {
            appDelegate.launcherPanelController?.refreshSnippetEmbeddingsAndSearch()
          }
        )
        .modelContainer(modelContainer)
      case .failure(let error):
        // ストアを開けなかった理由をユーザーが知れるよう、アプリを落とさずに出す。
        Text(verbatim: error.localizedDescription)
          .frame(minWidth: 480, minHeight: 320)
      }
    }
    .environment(appDelegate.newSnippetDraft)
    .environment(appDelegate.snippetEmbeddingRevision)
    .onAppear {
      appDelegate.openManagerWindow = {
        openWindow(id: managerWindowID)
      }
    }
  }
}
