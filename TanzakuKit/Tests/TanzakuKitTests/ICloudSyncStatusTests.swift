import CloudKit
import CoreData
import Foundation
import Testing

@testable import TanzakuKit

/// `iCloudSyncStatus(cloudKitContainerIdentifier:accountStatus:latestSyncErrorCode:)` と `cloudKitSyncErrorCode(error:)` が同期の状態を正しく決めるかを確かめる。
struct ICloudSyncStatusTests {
  @Test("CloudKit を使わない構成は、アカウントの状態によらず同期しないビルドとして出す")
  func noContainerIsUnavailableInThisBuild() {
    #expect(iCloudSyncStatus(cloudKitContainerIdentifier: nil, accountStatus: .available, latestSyncErrorCode: nil) == .unavailableInThisBuild)
    #expect(iCloudSyncStatus(cloudKitContainerIdentifier: nil, accountStatus: nil, latestSyncErrorCode: .quotaExceeded) == .unavailableInThisBuild)
  }

  @Test("アカウントの状態をまだ読んでいない時は確認中にする")
  func missingAccountStatusIsChecking() {
    #expect(iCloudSyncStatus(cloudKitContainerIdentifier: "iCloud.com.example.dummy", accountStatus: nil, latestSyncErrorCode: nil) == .checking)
  }

  @Test(
    "アカウントの状態ごとに状態を決める",
    arguments: [
      (CKAccountStatus.noAccount, ICloudSyncStatus.notSignedIn),
      (.restricted, .iCloudUnavailable),
      (.couldNotDetermine, .iCloudUnavailable),
      (.temporarilyUnavailable, .iCloudUnavailable),
      (.available, .syncing),
    ]
  )
  func accountStatusDecidesStatus(accountStatus: CKAccountStatus, expectedStatus: ICloudSyncStatus) {
    #expect(iCloudSyncStatus(cloudKitContainerIdentifier: "iCloud.com.example.dummy", accountStatus: accountStatus, latestSyncErrorCode: nil) == expectedStatus)
  }

  @Test("サインインしていて容量不足で失敗した時だけ容量不足にし、ほかの失敗は同期中のままにする")
  func quotaExceededOnlyWhenAvailable() {
    #expect(
      iCloudSyncStatus(cloudKitContainerIdentifier: "iCloud.com.example.dummy", accountStatus: .available, latestSyncErrorCode: .quotaExceeded) == .quotaExceeded
    )
    #expect(
      iCloudSyncStatus(cloudKitContainerIdentifier: "iCloud.com.example.dummy", accountStatus: .available, latestSyncErrorCode: .networkUnavailable) == .syncing
    )
    #expect(
      iCloudSyncStatus(cloudKitContainerIdentifier: "iCloud.com.example.dummy", accountStatus: .noAccount, latestSyncErrorCode: .quotaExceeded) == .notSignedIn
    )
  }

  @Test("成功と CloudKit 以外の失敗は理由なしにする")
  func nonCloudKitErrorHasNoCode() {
    #expect(cloudKitSyncErrorCode(error: nil) == nil)
    #expect(cloudKitSyncErrorCode(error: NSError(domain: NSCocoaErrorDomain, code: 134400)) == nil)
  }

  @Test("CloudKit の失敗はその理由を返す")
  func cloudKitErrorReturnsCode() {
    #expect(cloudKitSyncErrorCode(error: CKError(.quotaExceeded)) == .quotaExceeded)
    #expect(cloudKitSyncErrorCode(error: CKError(.networkFailure)) == .networkFailure)
  }

  @Test("終わった送信だけで失敗の理由を決め直し、受信・準備と終わっていないイベントでは決め直さない")
  func onlyFinishedExportDecidesSyncError() {
    #expect(isSyncErrorDecidingEvent(eventType: .export, isFinished: true))
    #expect(!isSyncErrorDecidingEvent(eventType: .export, isFinished: false))
    #expect(!isSyncErrorDecidingEvent(eventType: .import, isFinished: true))
    #expect(!isSyncErrorDecidingEvent(eventType: .setup, isFinished: true))
  }

  @Test("レコードごとの失敗に容量不足があれば容量不足を返し、無ければ partialFailure のまま返す")
  func partialFailureLooksIntoItemErrors() {
    let quotaExceededPartialFailure = CKError(
      .partialFailure,
      userInfo: [CKPartialErrorsByItemIDKey: [CKRecord.ID(recordName: "dummy-record"): CKError(.quotaExceeded)]]
    )
    let otherPartialFailure = CKError(
      .partialFailure,
      userInfo: [CKPartialErrorsByItemIDKey: [CKRecord.ID(recordName: "dummy-record"): CKError(.serverRecordChanged)]]
    )
    #expect(cloudKitSyncErrorCode(error: quotaExceededPartialFailure) == .quotaExceeded)
    #expect(cloudKitSyncErrorCode(error: otherPartialFailure) == .partialFailure)
  }
}
