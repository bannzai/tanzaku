import Foundation
import SwiftData
import Testing

@testable import TanzakuKit

/// `makeTanzakuModelContainer(storeLocation:syncedStoreCloudKitDatabase:)` が 2 つのストアを持つ `ModelContainer` を作るかを確かめる。
struct ModelContainerTanzakuTests {
  @Test("同期するストアと端末内のストアの 2 つの構成を持ち、モデルを重ねずに分ける")
  func configurationsSplitModels() throws {
    let container = try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none)
    let entityNamesByConfiguration = container.configurations.map { Set($0.schema?.entities.map(\.name) ?? []) }
    #expect(
      Set(entityNamesByConfiguration) == [
        ["Snippet", "Folder", "Tag", "SnippetGroup", "SnippetGroupItem"],
        ["SnippetEmbedding", "MCPClient"],
      ]
    )
  }

  @Test("ファイルの置き場所を渡すと、その URL に 2 つのストアのファイルを作る")
  func filesStoreLocationCreatesStoreFiles() throws {
    let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(at: directoryURL)
    }
    let syncedStoreURL = directoryURL.appendingPathComponent("Synced.store")
    let localStoreURL = directoryURL.appendingPathComponent("Local.store")

    let modelContext = ModelContext(
      try makeTanzakuModelContainer(
        storeLocation: .files(syncedStoreURL: syncedStoreURL, localStoreURL: localStoreURL),
        syncedStoreCloudKitDatabase: .none
      )
    )
    let snippet = Snippet(body: "echo dummy")
    modelContext.insert(snippet)
    modelContext.insert(SnippetEmbedding(snippetID: snippet.id, modelIdentifier: "dummy-model", sourceHash: "dummy-hash", vector: Data()))
    try modelContext.save()

    #expect(FileManager.default.fileExists(atPath: syncedStoreURL.path))
    #expect(FileManager.default.fileExists(atPath: localStoreURL.path))
  }

  @Test("iCloud の entitlement の無いプロセスでは、同期するストアを .automatic にしても CloudKit を使わずに開いて保存できる")
  func automaticWithoutEntitlementOpensAndSavesLocally() throws {
    let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(at: directoryURL)
    }

    let container = try makeTanzakuModelContainer(
      storeLocation: .files(syncedStoreURL: directoryURL.appendingPathComponent("Synced.store"), localStoreURL: directoryURL.appendingPathComponent("Local.store")),
      syncedStoreCloudKitDatabase: .automatic
    )
    let modelContext = ModelContext(container)
    modelContext.insert(Snippet(body: "echo dummy"))
    try modelContext.save()

    #expect(try modelContext.fetchCount(FetchDescriptor<Snippet>()) == 1)
    #expect(container.configurations.first { $0.name == syncedStoreConfigurationName }?.cloudKitContainerIdentifier == nil)
  }

  /// 共有シートの拡張は、本体アプリが CloudKit と同期して (persistent history を付けて) 開く同期するストアを `.none` で開いて書く。
  /// history を付けて開いたストアを history なしで開くと Core Data は読み取り専用にするため、`.none` でも history が付くことを確かめる。
  @Test("CloudKit を使わずに開いたストアにも persistent history が残る")
  func noneStoreKeepsPersistentHistory() throws {
    guard #available(macOS 15, iOS 18, *) else {
      return
    }
    let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(at: directoryURL)
    }

    let modelContext = ModelContext(
      try makeTanzakuModelContainer(
        storeLocation: .files(syncedStoreURL: directoryURL.appendingPathComponent("Synced.store"), localStoreURL: directoryURL.appendingPathComponent("Local.store")),
        syncedStoreCloudKitDatabase: .none
      )
    )
    modelContext.insert(Snippet(body: "echo dummy"))
    try modelContext.save()

    #expect(!(try modelContext.fetchHistory(HistoryDescriptor<DefaultHistoryTransaction>())).isEmpty)
  }
}
