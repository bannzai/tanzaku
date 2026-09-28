import SwiftData
import SwiftUI
import TanzakuKit

/// アプリのエントリポイント。
@main
struct TanzakuApp: App {
  /// スニペットのストア。
  private let modelContainer: ModelContainer
  /// 内蔵の MCP のサーバー。
  @State private var mcpServerController: MCPServerController

  /// ストアを開き、MCP のサーバーを起動する。
  init() {
    let modelContainer = makeAppModelContainer()
    self.modelContainer = modelContainer
    _mcpServerController = State(initialValue: MCPServerController(modelContainer: modelContainer, tokenStore: keychainMCPTokenStore()))
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .task {
          await mcpServerController.prepareEmbedder()
        }
    }
    .modelContainer(modelContainer)
    .environment(mcpServerController)
    .commands {
      #if DEBUG
        DeveloperCommands(controller: mcpServerController)
      #endif
    }

    Settings {
      TabView {
        AgentSettingsView()
          .tabItem {
            Label("AI Agents", systemImage: "cpu")
          }
      }
      .frame(width: 600)
      .frame(minHeight: 640)
    }
    .modelContainer(modelContainer)
    .environment(mcpServerController)
  }
}

/// アプリが使うストアを開く。ストアのファイルはアプリケーションサポートの中に置く。
///
/// 同期するストアの CloudKit は iCloud の同期を作る issue (#19) で有効にする。CI の ad-hoc 署名では iCloud の entitlement を満たせないため (`documents/data-model.md`「前提」)、それまでは同期しない。
/// ストアを開けないとスニペットを扱えず、アプリとして動けないため、開けなければ止める。
func makeAppModelContainer() -> ModelContainer {
  let storeDirectoryURL = URL.applicationSupportDirectory.appending(path: "Tanzaku", directoryHint: .isDirectory)
  do {
    try FileManager.default.createDirectory(at: storeDirectoryURL, withIntermediateDirectories: true)
    return try makeTanzakuModelContainer(
      storeLocation: .files(
        syncedStoreURL: storeDirectoryURL.appending(path: "Synced.store"),
        localStoreURL: storeDirectoryURL.appending(path: "Local.store")
      ),
      syncedStoreCloudKitDatabase: .none
    )
  } catch {
    fatalError("Could not open the snippet store: \(error)")
  }
}
