import Foundation
import Testing

@testable import TanzakuKit

/// `ICloudSyncMonitor` が CloudKit を使わない構成で `CKContainer` を作らずに同期しないビルドとして出すかを確かめる。
///
/// テストのプロセスは iCloud の entitlement を持たず、`CKContainer` を作ると例外で落ちるため、落ちずに終わることも確かめている。
@MainActor
struct ICloudSyncMonitorTests {
  @Test("CloudKit を使わない構成では、始めても同期しないビルドのまま")
  func withoutCloudKitStaysUnavailable() throws {
    let iCloudSyncMonitor = ICloudSyncMonitor(modelContainer: try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    #expect(iCloudSyncMonitor.status == .unavailableInThisBuild)
    iCloudSyncMonitor.start()
    #expect(iCloudSyncMonitor.status == .unavailableInThisBuild)
  }
}
