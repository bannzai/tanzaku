import SwiftData
import SwiftUI
import TanzakuKit
import os

/// iOS アプリのエントリポイント。ストアを開いて本体の画面を出し、意味検索の埋め込みモデルを用意する。
@main
struct TanzakuiOSApp: App {
  /// ストア。開けなかった時はその理由で、画面に出す。
  private let modelContainerResult = Result { try makeIOSModelContainer() }
  /// 意味検索の埋め込みモデル。資産のダウンロードが済むまでは `nil` で、その間は文字列の一致だけで検索する。
  @State private var snippetTextEmbedder: SnippetTextEmbedder?

  var body: some Scene {
    WindowGroup {
      switch modelContainerResult {
      case .success(let modelContainer):
        SnippetLibraryView()
          .environment(\.snippetTextEmbedder, snippetTextEmbedder)
          .modelContainer(modelContainer)
          .task {
            snippetTextEmbedder = await loadSnippetTextEmbedder()
          }
      case .failure(let error):
        ContentUnavailableView {
          Label("Could not open snippets", systemImage: "exclamationmark.triangle")
        } description: {
          Text(verbatim: String(describing: error))
        }
      }
    }
  }
}

extension EnvironmentValues {
  /// 意味検索の埋め込みモデル。一覧の検索とベクトルの作り直しに使う。
  @Entry var snippetTextEmbedder: SnippetTextEmbedder?
}

/// 起動時の準備の失敗の記録。スニペットの本文は入れない (`.claude/rules/snippet-content-handling.md`)。
private let appLogger = Logger(subsystem: "com.bannzai.tanzaku", category: "App")

/// 端末の優先言語の埋め込みモデルを用意する。資産が無ければダウンロードを待つ。用意できなければ `nil` を返し、一覧は文字列の一致だけで検索する。
private func loadSnippetTextEmbedder() async -> SnippetTextEmbedder? {
  let language = snippetEmbeddingLanguage(preferredLanguages: Locale.preferredLanguages)
  do {
    guard try await requestContextualEmbeddingAssets(language: language) else {
      return nil
    }
    return try makeContextualSnippetTextEmbedder(language: language)
  } catch {
    appLogger.error("Failed to load the embedding model: \(String(describing: error), privacy: .public)")
    return nil
  }
}
