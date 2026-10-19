import CloudKit
import Foundation

/// 同期するストアと iCloud との同期の状態。Mac の設定 (一般) と iOS のサイドバーに出す。
///
/// 同期しない状態でも、スニペットは端末内のストアに保存して使える (`documents/PROJECT.md`「同期」)。
public enum ICloudSyncStatus: Equatable, Sendable {
  /// このビルドは iCloud の entitlement を持たず、同期しない。CI・simtunnel のビルド (`documents/DIRECTION.md`「決めたこと」)。
  case unavailableInThisBuild
  /// iCloud のアカウントの状態をまだ読んでいない。
  case checking
  /// iCloud にサインインしていて、同期している。
  case syncing
  /// iCloud にサインインしていない。
  case notSignedIn
  /// iCloud の容量が足りず、変更を送れない。
  case quotaExceeded
  /// 制限 (スクリーンタイム・管理されたデバイス) や一時的な理由で iCloud を使えない。
  case iCloudUnavailable
}

/// 同期の状態を決める。
///
/// - Parameters:
///   - cloudKitContainerIdentifier: 同期するストアが使う iCloud コンテナ。`nil` は CloudKit を使わない構成。
///   - accountStatus: iCloud のアカウントの状態。`nil` はまだ読んでいない。
///   - latestSyncErrorCode: 最後に終わった同期の失敗の理由。成功した時とまだ同期していない時は `nil`。
public func iCloudSyncStatus(
  cloudKitContainerIdentifier: String?,
  accountStatus: CKAccountStatus?,
  latestSyncErrorCode: CKError.Code?
) -> ICloudSyncStatus {
  guard cloudKitContainerIdentifier != nil else {
    return .unavailableInThisBuild
  }
  guard let accountStatus else {
    return .checking
  }
  switch accountStatus {
  case .available:
    return latestSyncErrorCode == .quotaExceeded ? .quotaExceeded : .syncing
  case .noAccount:
    return .notSignedIn
  case .restricted, .couldNotDetermine, .temporarilyUnavailable:
    return .iCloudUnavailable
  @unknown default:
    return .iCloudUnavailable
  }
}

/// 終わった同期の失敗から、状態を決めるのに使う CloudKit のエラーの理由を取り出す。成功 (`error` が `nil`) と CloudKit 以外の失敗は `nil`。
///
/// 複数のレコードを送る同期では、容量不足が `partialFailure` のレコードごとのエラーの中にだけ入ることがあるため、その中も見る。
public func cloudKitSyncErrorCode(error: (any Error)?) -> CKError.Code? {
  guard let cloudKitError = error as? CKError else {
    return nil
  }
  if cloudKitError.code == .partialFailure,
    cloudKitError.partialErrorsByItemID?.values.contains(where: { ($0 as? CKError)?.code == .quotaExceeded }) == true
  {
    return .quotaExceeded
  }
  return cloudKitError.code
}

/// 同期の状態の説明の文言。どの状態でもスニペットを端末に保存して使えることを伝える。
public func iCloudSyncStatusDescription(status: ICloudSyncStatus) -> String {
  switch status {
  case .unavailableInThisBuild:
    String(localized: "This build doesn’t sync with iCloud. Snippets are kept on this device.", bundle: .module)
  case .checking:
    String(localized: "Checking iCloud…", bundle: .module)
  case .syncing:
    String(localized: "Snippets sync with your other devices through iCloud.", bundle: .module)
  case .notSignedIn:
    String(localized: "You aren’t signed in to iCloud. Snippets are kept on this device until you sign in.", bundle: .module)
  case .quotaExceeded:
    String(localized: "Your iCloud storage is full, so changes aren’t synced. Snippets are kept on this device.", bundle: .module)
  case .iCloudUnavailable:
    String(localized: "iCloud isn’t available right now. Snippets are kept on this device.", bundle: .module)
  }
}

/// 同期の状態の SF Symbols の名前。同期している時だけ印を付け、ほかは同期していないことを示す。
public func iCloudSyncStatusSystemImage(status: ICloudSyncStatus) -> String {
  switch status {
  case .syncing:
    "checkmark.icloud"
  case .checking:
    "icloud"
  case .unavailableInThisBuild, .notSignedIn, .iCloudUnavailable:
    "icloud.slash"
  case .quotaExceeded:
    "exclamationmark.icloud"
  }
}
