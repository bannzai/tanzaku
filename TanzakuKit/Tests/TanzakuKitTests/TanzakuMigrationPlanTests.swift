import Foundation
import SwiftData
import Testing

@testable import TanzakuKit

/// 移行の計画がスキーマの版の並びと合っているか、前の版のストアを今の版で開けるかを確かめる。
struct TanzakuMigrationPlanTests {
  @Test("SchemaV1 と SchemaV2 を古い順に持ち、その間の移行段階を 1 つ持つ")
  func schemasAndStages() {
    #expect(TanzakuMigrationPlan.schemas.map { ObjectIdentifier($0) } == [ObjectIdentifier(SchemaV1.self), ObjectIdentifier(SchemaV2.self)])
    #expect(TanzakuMigrationPlan.stages.count == 1)
  }

  @Test("SchemaV1 のモデルは同期するストアと端末内のストアのどちらか一方だけに入る")
  func schemaV1ModelsAreSplitIntoStores() {
    let syncedModelNames = Set(SchemaV1.syncedModels.map { String(describing: $0) })
    let localModelNames = Set(SchemaV1.localModels.map { String(describing: $0) })
    #expect(syncedModelNames.isDisjoint(with: localModelNames))
    #expect(SchemaV1.models.count == syncedModelNames.count + localModelNames.count)
    #expect(SchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
  }

  @Test("SchemaV2 のモデルは SchemaV1 と同じ分け方で、同期するストアと端末内のストアのどちらか一方だけに入る")
  func schemaV2ModelsAreSplitIntoStores() {
    let syncedModelNames = Set(SchemaV2.syncedModels.map { String(describing: $0) })
    let localModelNames = Set(SchemaV2.localModels.map { String(describing: $0) })
    #expect(syncedModelNames.isDisjoint(with: localModelNames))
    #expect(SchemaV2.models.count == syncedModelNames.count + localModelNames.count)
    #expect(syncedModelNames == Set(SchemaV1.syncedModels.map { String(describing: $0) }))
    #expect(localModelNames == Set(SchemaV1.localModels.map { String(describing: $0) }))
    #expect(SchemaV2.versionIdentifier == Schema.Version(2, 0, 0))
  }

  @Test("SchemaV1 で保存したファイルのストアを今の版で開くと、データが残り lastUsedAt は nil になる")
  func migratesSchemaV1StoreToCurrentVersion() throws {
    let storeDirectoryURL = FileManager.default.temporaryDirectory.appending(path: "TanzakuMigrationPlanTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: storeDirectoryURL, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(at: storeDirectoryURL)
    }
    let syncedStoreURL = storeDirectoryURL.appending(path: "Synced.store")
    let localStoreURL = storeDirectoryURL.appending(path: "Local.store")
    let snippetID = try saveSchemaV1Store(syncedStoreURL: syncedStoreURL, localStoreURL: localStoreURL)

    let modelContext = ModelContext(
      try makeTanzakuModelContainer(storeLocation: .files(syncedStoreURL: syncedStoreURL, localStoreURL: localStoreURL), syncedStoreCloudKitDatabase: .none)
    )
    let snippets = try modelContext.fetch(FetchDescriptor<Snippet>())
    #expect(snippets.map(\.id) == [snippetID])
    #expect(snippets.map(\.keyword) == ["envkey"])
    #expect(snippets.map(\.lastUsedAt) == [nil])
    #expect(try modelContext.fetch(FetchDescriptor<SnippetGroup>()).flatMap { ($0.items ?? []).compactMap(\.snippet?.id) } == [snippetID])
    #expect(try modelContext.fetch(FetchDescriptor<SnippetEmbedding>()).map(\.snippetID) == [snippetID])

    let usedAt = Date(timeIntervalSince1970: 1_000)
    try recordSnippetUse(snippet: try #require(snippets.first), usedAt: usedAt, modelContext: modelContext)
    #expect(try ModelContext(modelContext.container).fetch(FetchDescriptor<Snippet>()).map(\.lastUsedAt) == [usedAt])
  }

  /// `SchemaV1` だけを知る (移行の計画を持たない) コンテナで、スニペット・スニペットグループ・意味検索のベクトルをファイルのストアに保存し、スニペットの識別子を返す。
  ///
  /// 関数を抜けるとコンテナが解放され、今の版のコンテナが同じファイルを開き直せる。
  private func saveSchemaV1Store(syncedStoreURL: URL, localStoreURL: URL) throws -> UUID {
    let modelContext = ModelContext(
      try ModelContainer(
        for: Schema(versionedSchema: SchemaV1.self),
        configurations: [
          ModelConfiguration(syncedStoreConfigurationName, schema: Schema(SchemaV1.syncedModels), url: syncedStoreURL, cloudKitDatabase: .none),
          ModelConfiguration(localStoreConfigurationName, schema: Schema(SchemaV1.localModels), url: localStoreURL, cloudKitDatabase: .none),
        ]
      )
    )
    let snippet = SchemaV1.Snippet(body: "export API_TOKEN=dummy-token-for-test")
    snippet.keyword = "envkey"
    let snippetGroup = SchemaV1.SnippetGroup(name: "dummy-group")
    let snippetGroupItem = SchemaV1.SnippetGroupItem(sortIndex: 0)
    modelContext.insert(snippet)
    modelContext.insert(snippetGroup)
    modelContext.insert(snippetGroupItem)
    snippetGroupItem.group = snippetGroup
    snippetGroupItem.snippet = snippet
    modelContext.insert(SchemaV1.SnippetEmbedding(snippetID: snippet.id, modelIdentifier: "dummy-model", sourceHash: "dummy-hash", vector: Data([1, 2, 3, 4])))
    try modelContext.save()
    return snippet.id
  }
}
