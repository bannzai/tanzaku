import Foundation
import SwiftData
import TanzakuKit

/// Mac アプリのストアのファイルを置くフォルダ。Application Support の中に置く (App Sandbox の中ではアプリのコンテナの Application Support になる)。
func macStoreDirectoryURL() -> URL {
  URL.applicationSupportDirectory.appending(path: "Tanzaku", directoryHint: .isDirectory)
}

/// Mac アプリの `ModelContainer` を作る。ストアのファイルのフォルダが無ければ作り、あればそのまま使うため、何度呼んでも同じストアを開く。
///
/// iCloud (CloudKit) との同期は同期の issue (#19) で有効にするまで切っておく。CI の ad-hoc 署名では iCloud の entitlement を満たせず (`documents/data-model.md`「前提」)、同期を有効にすると CI のビルドで作ったアプリが起動できないため。
func makeMacModelContainer() throws -> ModelContainer {
  try FileManager.default.createDirectory(at: macStoreDirectoryURL(), withIntermediateDirectories: true)
  return try makeTanzakuModelContainer(
    storeLocation: .files(
      syncedStoreURL: macStoreDirectoryURL().appending(path: "Synced.store"),
      localStoreURL: macStoreDirectoryURL().appending(path: "Local.store")
    ),
    syncedStoreCloudKitDatabase: .none
  )
}
