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
}
