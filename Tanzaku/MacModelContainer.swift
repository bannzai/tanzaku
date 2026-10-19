import Foundation
import SwiftData
import TanzakuKit

/// Mac アプリのストアのファイルを置くフォルダ。Application Support の中に置く (App Sandbox の中ではアプリのコンテナの Application Support になる)。
func macStoreDirectoryURL() -> URL {
  URL.applicationSupportDirectory.appending(path: "Tanzaku", directoryHint: .isDirectory)
}

/// Mac アプリの `ModelContainer` を作る。ストアのファイルのフォルダが無ければ作り、あればそのまま使うため、何度呼んでも同じストアを開く。
///
/// 同期するストアは entitlement の iCloud コンテナと同期する (`.automatic`)。CI の ad-hoc 署名・`DebugUnsigned` は iCloud の entitlement を外したファイルで署名するため (`documents/DIRECTION.md`「決めたこと」)、その時は同期せずに端末内だけで動く。
func makeMacModelContainer() throws -> ModelContainer {
  try FileManager.default.createDirectory(at: macStoreDirectoryURL(), withIntermediateDirectories: true)
  return try makeTanzakuModelContainer(
    storeLocation: .files(
      syncedStoreURL: macStoreDirectoryURL().appending(path: "Synced.store"),
      localStoreURL: macStoreDirectoryURL().appending(path: "Local.store")
    ),
    syncedStoreCloudKitDatabase: .automatic
  )
}
