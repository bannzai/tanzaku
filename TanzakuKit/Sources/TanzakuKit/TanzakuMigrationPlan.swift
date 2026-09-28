import SwiftData

/// スキーマの版の並びと、版の間の移行段階。モデルを変える時は新しい版を `schemas` の末尾に、移行段階を `stages` に足す (`.claude/rules/data-model.md`)。
public enum TanzakuMigrationPlan: SchemaMigrationPlan {
  /// 古い順に並べたスキーマの版。
  public static var schemas: [any VersionedSchema.Type] {
    [SchemaV1.self]
  }

  /// 隣り合う版の間の移行段階。版が 1 つのうちは無い。
  public static var stages: [MigrationStage] {
    []
  }
}
