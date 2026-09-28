# データモデルの変更

- モデルの仕様は `documents/data-model.md` が正。`@Model` を足す・変える時は同じ変更で `documents/data-model.md` を更新する
- 同期するストアのモデルは `documents/data-model.md`「CloudKit と両立させるための制約」を守る。守らないと CloudKit と同期する `ModelContainer` の初期化が失敗する
- モデルの変更は `VersionedSchema` の新しい版と `SchemaMigrationPlan` の移行段階として足し、既存の版を書き換えない
- 属性・モデルの削除と改名はしない (本番の CloudKit スキーマは追加しかできない)
- スニペットの本文をテストの fixture に入れる時は `.claude/rules/snippet-content-handling.md` に従い偽の値を使う
