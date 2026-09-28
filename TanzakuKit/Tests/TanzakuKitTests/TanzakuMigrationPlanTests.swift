import SwiftData
import Testing

@testable import TanzakuKit

/// 移行の計画がスキーマの版の並びと合っているかを確かめる。
struct TanzakuMigrationPlanTests {
  @Test("最初の版だけを持ち、移行段階は無い")
  func schemasAndStages() {
    #expect(TanzakuMigrationPlan.schemas.map { ObjectIdentifier($0) } == [ObjectIdentifier(SchemaV1.self)])
    #expect(TanzakuMigrationPlan.stages.isEmpty)
  }

  @Test("SchemaV1 のモデルは同期するストアと端末内のストアのどちらか一方だけに入る")
  func schemaV1ModelsAreSplitIntoStores() {
    let syncedModelNames = Set(SchemaV1.syncedModels.map { String(describing: $0) })
    let localModelNames = Set(SchemaV1.localModels.map { String(describing: $0) })
    #expect(syncedModelNames.isDisjoint(with: localModelNames))
    #expect(SchemaV1.models.count == syncedModelNames.count + localModelNames.count)
    #expect(SchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
  }
}
