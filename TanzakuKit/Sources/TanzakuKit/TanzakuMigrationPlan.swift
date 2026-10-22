import SwiftData

/// スキーマの版の並びと、版の間の移行段階。モデルを変える時は新しい版を `schemas` の末尾に、移行段階を `stages` に足す (`.claude/rules/data-model.md`)。
public enum TanzakuMigrationPlan: SchemaMigrationPlan {
  /// 古い順に並べたスキーマの版。
  public static var schemas: [any VersionedSchema.Type] {
    [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self]
  }

  /// 隣り合う版の間の移行段階。
  ///
  /// `SchemaV1` から `SchemaV2` へは `Snippet.lastUsedAt` (Optional) を足すだけで、既存のスニペットは `nil` (使ったことが無い) のままでよいため、値を書き換えない lightweight の移行にする。
  /// `SchemaV2` から `SchemaV3` へは `Snippet` の添付の属性 (Optional) を足すだけで、既存のスニペットは本文のスニペット (添付なし) のままでよいため、同じく lightweight の移行にする。
  /// `SchemaV3` から `SchemaV4` へは `Snippet.mcpApprovedContentHash` (既定 `nil`) を足すだけで、既存の MCP のクライアントが作成・更新したスニペットは承認待ちになればよいため、同じく lightweight の移行にする。
  public static var stages: [MigrationStage] {
    [
      .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
      .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self),
      .lightweight(fromVersion: SchemaV3.self, toVersion: SchemaV4.self),
    ]
  }
}
