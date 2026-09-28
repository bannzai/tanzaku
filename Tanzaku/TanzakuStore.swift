import Foundation
import OSLog
import SwiftData
import TanzakuKit

/// Mac アプリのストアのファイルの置き場所。Application Support の `Tanzaku` ディレクトリに、同期するストアと端末内のストアを置く。
///
/// Debug ビルドは `TanzakuDebug` ディレクトリに分ける。Debug ビルドは普段使いの Release ビルド (`make macos`) と同じ bundle ID で同じ Application Support を使うため、
/// 分けないと動作確認の見本データ (Debug メニューの「Insert Sample Data」) が開発者のスニペットに混ざるため。
/// ディレクトリが無い時は作る。既にあれば何もしないため、何度呼んでも同じ結果になる。
func tanzakuStoreLocation() throws -> ModelStoreLocation {
  #if DEBUG
    let storeDirectoryName = "TanzakuDebug"
  #else
    let storeDirectoryName = "Tanzaku"
  #endif
  let storeDirectoryURL = URL.applicationSupportDirectory.appending(path: storeDirectoryName, directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: storeDirectoryURL, withIntermediateDirectories: true)
  return .files(
    syncedStoreURL: storeDirectoryURL.appending(path: "Synced.store"),
    localStoreURL: storeDirectoryURL.appending(path: "Local.store")
  )
}

/// Mac アプリの `ModelContainer` を作る。
///
/// 同期するストアの CloudKit は同期の issue ( https://github.com/bannzai/tanzaku/issues/19 ) で有効にする。
/// それまでは iCloud の entitlement と iCloud コンテナが無く、CI の ad-hoc 署名でも CloudKit を使えないため、`.none` にする。
func makeMacModelContainer() throws -> ModelContainer {
  try makeTanzakuModelContainer(storeLocation: try tanzakuStoreLocation(), syncedStoreCloudKitDatabase: .none)
}

/// スニペットの変更を保存し、意味検索のベクトルを今のスニペットに合わせる。スニペットの追加・更新・削除の後に呼ぶ。
///
/// 変更の保存に失敗した時だけエラーを投げる。ベクトルは本文から作り直せる派生データで、作れなくても保存したスニペットは使えるため、失敗はログに残して続ける。
/// ログには本文を入れない (`.claude/rules/snippet-content-handling.md`)。
func saveSnippetChanges(modelContext: ModelContext, embedder: SnippetTextEmbedder?) throws {
  try modelContext.save()
  guard let embedder else {
    return
  }
  do {
    try updateSnippetEmbeddings(modelContext: modelContext, embedder: embedder)
    try modelContext.save()
  } catch {
    Logger(subsystem: "com.bannzai.tanzaku", category: "SnippetEmbedding").error("Failed to update snippet embeddings: \(error.localizedDescription, privacy: .public)")
  }
}

/// 端末の優先言語の埋め込みモデルの資産を用意し、意味検索に使う埋め込みモデルを作って、すべてのスニペットのベクトルを合わせる。アプリの起動時に呼ぶ。
///
/// 資産が無い・ダウンロードできない時は `nil` を返し、呼び出し側は意味検索なしで検索する。
func prepareSnippetTextEmbedder(modelContext: ModelContext) async -> SnippetTextEmbedder? {
  let language = snippetEmbeddingLanguage(preferredLanguages: Locale.preferredLanguages)
  do {
    guard try await requestContextualEmbeddingAssets(language: language), let embedder = try makeContextualSnippetTextEmbedder(language: language) else {
      return nil
    }
    try saveSnippetChanges(modelContext: modelContext, embedder: embedder)
    return embedder
  } catch {
    Logger(subsystem: "com.bannzai.tanzaku", category: "SnippetEmbedding").error("Failed to prepare the snippet text embedder: \(error.localizedDescription, privacy: .public)")
    return nil
  }
}
