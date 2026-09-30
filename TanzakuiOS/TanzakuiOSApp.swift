import SwiftData
import SwiftUI
import TanzakuKit

/// iOS アプリのエントリポイント。ストアを開いて本体の画面を出し、意味検索の埋め込みモデルを用意する。
@main
struct TanzakuiOSApp: App {
  /// ストア。開けなかった時はその理由で、画面に出す。
  private let modelContainerResult: Result<ModelContainer, any Error>
  /// 意味検索の埋め込みモデルとベクトル。ストアを開けなかった時は `nil`。
  private let snippetEmbeddingController: SnippetEmbeddingController?
  /// アプリが前面に戻ったことを知る。共有シートの拡張 (別のプロセス) が保存したスニペットのベクトルを作るため。
  @Environment(\.scenePhase) private var scenePhase

  /// ストアを開き、同じストアでベクトルを作る `SnippetEmbeddingController` を作る。どちらもアプリで 1 つだけ持つため、`App` の init で作る。
  init() {
    modelContainerResult = iosModelContainerResult
    snippetEmbeddingController = (try? modelContainerResult.get()).map { SnippetEmbeddingController(modelContainer: $0) }
  }

  var body: some Scene {
    WindowGroup {
      switch (modelContainerResult, snippetEmbeddingController) {
      case (.success(let modelContainer), .some(let snippetEmbeddingController)):
        SnippetLibraryView()
          .environment(snippetEmbeddingController)
          .modelContainer(modelContainer)
          .task {
            await snippetEmbeddingController.loadEmbeddingModel()
          }
          .onChange(of: scenePhase) { _, newScenePhase in
            // 拡張は埋め込みモデルを読み込まずに保存するため、前面に戻るたびにベクトルを保存済みのスニペットに合わせる。変わっていないベクトルは作り直さない。
            guard newScenePhase == .active else {
              return
            }
            Task {
              await snippetEmbeddingController.refreshEmbeddings()
            }
          }
      case (.success, .none):
        // ストアを開けた時は `SnippetEmbeddingController` も作るため (`init()`)、ここには来ない。
        EmptyView()
      case (.failure(let error), _):
        ContentUnavailableView {
          Label("Could not open snippets", systemImage: "exclamationmark.triangle")
        } description: {
          Text(verbatim: String(describing: error))
        }
      }
    }
  }
}
