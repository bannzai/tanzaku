import Foundation
import SwiftData
import TanzakuKit

/// 本体アプリ・共有シート・App Intents・カスタムキーボードが同じストアを使うための App Group (`documents/data-model.md`「ストアの分け方」)。
let tanzakuAppGroupIdentifier = "group.com.bannzai.tanzaku"

/// iOS アプリのストアを開けなかった理由。`description` は画面にそのまま表示する。
enum IOSModelContainerError: Error, CustomStringConvertible {
  /// App Group の共有コンテナの場所を取れなかった (entitlement に App Group が無い)。
  case appGroupContainerUnavailable

  /// 画面にそのまま表示する文言。
  var description: String {
    switch self {
    case .appGroupContainerUnavailable:
      "The shared container of the App Group \(tanzakuAppGroupIdentifier) is unavailable."
    }
  }
}

/// iOS アプリの `ModelContainer` を作る。ストアのファイルは App Group の共有コンテナの `Tanzaku/` に置く。フォルダが無ければ作り、あればそのまま使うため、何度呼んでも同じストアを開く。
///
/// iCloud (CloudKit) との同期は同期の issue (#19) で有効にするまで切っておく。iCloud コンテナが未作成で (#5)、CI・simtunnel の署名しないビルドでは iCloud の entitlement を満たせないため。
///
/// `mainContext` の自動保存は切る。編集画面は `@Model` を直接書き換え、検査を通った時だけ保存し、取り消した時は `rollback()` で戻すため。自動保存があると検査の前の値が保存される。
func makeIOSModelContainer() throws -> ModelContainer {
  guard let appGroupContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: tanzakuAppGroupIdentifier) else {
    throw IOSModelContainerError.appGroupContainerUnavailable
  }
  let storeDirectoryURL = appGroupContainerURL.appending(path: "Tanzaku", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: storeDirectoryURL, withIntermediateDirectories: true)
  let modelContainer = try makeTanzakuModelContainer(
    storeLocation: .files(
      syncedStoreURL: storeDirectoryURL.appending(path: "Synced.store"),
      localStoreURL: storeDirectoryURL.appending(path: "Local.store")
    ),
    syncedStoreCloudKitDatabase: .none
  )
  modelContainer.mainContext.autosaveEnabled = false
  return modelContainer
}
