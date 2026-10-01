import Foundation
import SwiftData

/// ストアのファイルの置き場所。同期するストアと端末内のストアの 2 つを持つ (`documents/data-model.md`「ストアの分け方」)。
public enum ModelStoreLocation {
  /// 2 つのストアのファイルの URL。iOS では本体アプリと拡張が同じストアを使うため、App Group の共有コンテナの中を渡す。
  case files(syncedStoreURL: URL, localStoreURL: URL)
  /// ファイルを作らずメモリにだけ置く。テストとプレビューで使う。
  case inMemory
}

/// 同期するストアの `ModelConfiguration` の名前。メモリに置く時に 2 つのストアを区別するために要る。移行のテストが前の版のストアを同じ名前で作るため private にしない。
let syncedStoreConfigurationName = "Synced"
/// 端末内のストアの `ModelConfiguration` の名前。移行のテストが前の版のストアを同じ名前で作るため private にしない。
let localStoreConfigurationName = "Local"

/// 同期するストアと端末内のストアの 2 つの `ModelConfiguration` から、アプリと拡張が共通に使う `ModelContainer` を作る。
///
/// CloudKit は同期するストアだけに効かせる。端末内のストアの意味検索のベクトルは端末の OS・埋め込みモデルの版で変わり、MCP の接続先はその Mac に属するため、常に同期しない。
public func makeTanzakuModelContainer(
  storeLocation: ModelStoreLocation,
  syncedStoreCloudKitDatabase: ModelConfiguration.CloudKitDatabase
) throws -> ModelContainer {
  let syncedSchema = Schema(SchemaV2.syncedModels)
  let localSchema = Schema(SchemaV2.localModels)
  let configurations: [ModelConfiguration] =
    switch storeLocation {
    case .files(let syncedStoreURL, let localStoreURL):
      [
        ModelConfiguration(
          syncedStoreConfigurationName,
          schema: syncedSchema,
          url: syncedStoreURL,
          cloudKitDatabase: syncedStoreCloudKitDatabase
        ),
        ModelConfiguration(localStoreConfigurationName, schema: localSchema, url: localStoreURL, cloudKitDatabase: .none),
      ]
    case .inMemory:
      [
        ModelConfiguration(
          syncedStoreConfigurationName,
          schema: syncedSchema,
          isStoredInMemoryOnly: true,
          cloudKitDatabase: syncedStoreCloudKitDatabase
        ),
        ModelConfiguration(localStoreConfigurationName, schema: localSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none),
      ]
    }
  return try ModelContainer(
    for: Schema(versionedSchema: SchemaV2.self),
    migrationPlan: TanzakuMigrationPlan.self,
    configurations: configurations
  )
}
