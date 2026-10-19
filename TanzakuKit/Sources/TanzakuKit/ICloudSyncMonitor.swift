import CloudKit
import Combine
import CoreData
import Foundation
import Observation
import SwiftData

/// 本体アプリの同期の状態 (`ICloudSyncStatus`) を持つ。iCloud のアカウントの変化と、同期の終わり (`NSPersistentCloudKitContainer` のイベント) を受けて状態を変える。
///
/// `CKContainer` は iCloud の entitlement の無いプロセスで作ると例外で落ちるため、同期するストアが CloudKit を使う時 (コンテナの識別子がある時) だけ作る。
/// 拡張は同期しないため作らない。Mac のユニットテストは iCloud の entitlement を外したアプリの中で走るため (`documents/DIRECTION.md`「決めたこと」)、テストでも作らない。
@MainActor
@Observable
public final class ICloudSyncMonitor {
  /// 今の同期の状態。
  public private(set) var status: ICloudSyncStatus
  /// 同期するストアが使う iCloud コンテナ。`nil` は CloudKit を使わない構成。
  private let cloudKitContainerIdentifier: String?
  /// iCloud のアカウントの状態。`nil` はまだ読んでいない。
  private var accountStatus: CKAccountStatus?
  /// 最後に終わった同期の失敗の理由。
  private var latestSyncErrorCode: CKError.Code?
  /// アカウントの変化と同期のイベントの購読。
  @ObservationIgnored private var notificationSubscriptions: Set<AnyCancellable> = []

  /// `modelContainer` の同期するストアの構成から、CloudKit を使うかとコンテナを読む。
  public init(modelContainer: ModelContainer) {
    cloudKitContainerIdentifier = modelContainer.configurations.first { $0.name == syncedStoreConfigurationName }?.cloudKitContainerIdentifier
    status = iCloudSyncStatus(cloudKitContainerIdentifier: cloudKitContainerIdentifier, accountStatus: nil, latestSyncErrorCode: nil)
  }

  /// アカウントの状態を読み、アカウントの変化と同期のイベントの購読を始める。何度呼んでも購読は 1 つにする。CloudKit を使わない構成では何もしない。
  public func start() {
    guard let cloudKitContainerIdentifier, notificationSubscriptions.isEmpty else {
      return
    }
    NotificationCenter.default.publisher(for: .CKAccountChanged)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        MainActor.assumeIsolated {
          self?.refreshAccountStatus(cloudKitContainerIdentifier: cloudKitContainerIdentifier)
        }
      }
      .store(in: &notificationSubscriptions)
    Self.finishedSyncErrorCodes()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] syncErrorCode in
        MainActor.assumeIsolated {
          self?.latestSyncErrorCode = syncErrorCode
          self?.updateStatus()
        }
      }
      .store(in: &notificationSubscriptions)
    refreshAccountStatus(cloudKitContainerIdentifier: cloudKitContainerIdentifier)
  }

  /// 終わった同期のイベントごとに、失敗の理由 (成功は `nil`) を流す。
  ///
  /// イベントは Core Data の内部のキューから通知されるため、main actor の外で動く nonisolated な関数で組み立てる。
  private nonisolated static func finishedSyncErrorCodes() -> AnyPublisher<CKError.Code?, Never> {
    NotificationCenter.default.publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
      .compactMap { notification in
        notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event
      }
      .filter { event in
        event.endDate != nil
      }
      .map { event in
        cloudKitSyncErrorCode(error: event.error)
      }
      .eraseToAnyPublisher()
  }

  /// iCloud のアカウントの状態を読み直す。読めなかった時は判定できなかったものとして扱う。
  private func refreshAccountStatus(cloudKitContainerIdentifier: String) {
    Task {
      do {
        accountStatus = try await CKContainer(identifier: cloudKitContainerIdentifier).accountStatus()
      } catch {
        accountStatus = .couldNotDetermine
      }
      updateStatus()
    }
  }

  /// 今のアカウントの状態と同期の失敗から状態を決め直す。
  private func updateStatus() {
    status = iCloudSyncStatus(
      cloudKitContainerIdentifier: cloudKitContainerIdentifier,
      accountStatus: accountStatus,
      latestSyncErrorCode: latestSyncErrorCode
    )
  }
}
