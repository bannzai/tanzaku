# データモデル

スニペットの保存に使う SwiftData のモデルの仕様。要件と決定の経緯は `documents/DIRECTION.md` にあり、ここではそれを満たす保存の形だけを書く。変更時の規律は `.claude/rules/data-model.md`。

## 前提

- 保存は SwiftData。バックエンドは持たない
- 今は macOS アプリだけだが、iOS アプリへの展開を見込み、Mac と iOS の間を iCloud (CloudKit) で同期できる形で最初から定義する。同期を有効にする時期は iOS 版に着手する時に決める (それまでは同期しない)
- macOS 版は Developer ID で配布する。Developer ID で署名したアプリも Developer ID 用の provisioning profile があれば CloudKit を使える ( https://developer.apple.com/developer-id/ )

## ストアの分け方

| ストア | 置くモデル | 同期 | 理由 |
| --- | --- | --- | --- |
| 同期するストア | `Snippet`・`Folder`・`Tag`・`SnippetGroup`・`SnippetGroupItem` | iOS 版で有効にする (`ModelConfiguration` の `cloudKitDatabase`。それまでは `.none`) | ユーザーのデータで、どの端末でも同じであるべきもの |
| 端末内のストア | `SnippetEmbedding`・`MCPClient` | しない (`cloudKitDatabase: .none`) | 意味検索のベクトルは端末の OS・埋め込みモデルの版で変わり、同期すると別の版のベクトルが混ざる。MCP の接続先はその Mac の localhost サーバーに属し、iOS には無い |

2 つの `ModelConfiguration` を 1 つの `ModelContainer` にまとめる。ストア間はリレーションを張れないため、端末内のストアからは `Snippet.id` (UUID) で参照する。

## CloudKit と両立させるための制約

同期しない今も、同期するストアのモデルは次を守る (CloudKit の制約: https://developer.apple.com/documentation/coredata/creating-a-core-data-model-for-cloudkit 、 https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices )。

- すべての属性は Optional か既定値を持つ
- `@Attribute(.unique)` を使わない。一意であるべき値 (キーワード) はアプリのコードで保証する
- リレーションはすべて Optional。削除ルールに `.deny` を使わない
- 本番の CloudKit スキーマは追加しかできない。属性・モデルの削除や改名はせず、使わなくなった属性は残して読まない

## モデル

### Snippet

1 件のスニペット。

| 属性 | 型 | 既定 | 意味 |
| --- | --- | --- | --- |
| `id` | `UUID` | `UUID()` | ストアをまたいだ参照・MCP のツールで使う識別子 |
| `body` | `String` | `""` | 出力する本文。必須 (空の本文では保存させない。アプリのコードで検査する) |
| `title` | `String?` | `nil` | 無ければ一覧・ランチャーで本文の 1 行目を表示する |
| `keyword` | `String?` | `nil` | キーワード展開・ランチャーで一致させる略語。`SnippetGroup.keyword` と同じ名前空間で一意 |
| `language` | `String?` | `nil` | シンタックスハイライトの言語。`nil` はプレーンテキスト |
| `colorRawValue` | `String?` | `nil` | 色 (朱・藍・松葉・山吹・紫) の raw value。`nil` は色なし |
| `folder` | `Folder?` | `nil` | 0〜1 個のフォルダ |
| `tags` | `[Tag]?` | `[]` | 0 個以上のタグ |
| `createdAt` / `updatedAt` | `Date` | `.now` | |
| `createdByKind` / `updatedByKind` | `String` | `"user"` | 作成・更新した主体の種類 (`user` / `mcp`)。「AI エージェントが追加」の絞り込みを `#Predicate` で書くため、Codable の複合型にせず平の属性にする |
| `createdByClientName` / `updatedByClientName` | `String?` | `nil` | 主体が `mcp` の時の MCP クライアント名 |

### Folder

| 属性 | 型 | 既定 | 意味 |
| --- | --- | --- | --- |
| `id` | `UUID` | `UUID()` | |
| `name` | `String` | `""` | |
| `snippets` | `[Snippet]?` | `[]` | 削除ルールは `.nullify` (フォルダを消してもスニペットは残る) |

### Tag

| 属性 | 型 | 既定 | 意味 |
| --- | --- | --- | --- |
| `id` | `UUID` | `UUID()` | |
| `name` | `String` | `""` | |
| `snippets` | `[Snippet]?` | `[]` | 削除ルールは `.nullify` |

### SnippetGroup

キーワードを打つと、入力欄のキャレットの位置にメニューを出して、登録したスニペットから 1 つを選ばせるまとまり (例: `;focus-app` で `deploy` / `release` / `run-test`)。

| 属性 | 型 | 既定 | 意味 |
| --- | --- | --- | --- |
| `id` | `UUID` | `UUID()` | |
| `name` | `String` | `""` | 管理画面での表示名 |
| `keyword` | `String?` | `nil` | メニューを出すキーワード。`Snippet.keyword` と同じ名前空間で一意 |
| `items` | `[SnippetGroupItem]?` | `[]` | 削除ルールは `.cascade` |
| `createdAt` / `updatedAt` | `Date` | `.now` | |

### SnippetGroupItem

グループのメニューに並ぶ 1 項目。1 つのスニペットを複数のグループに入れられるよう、順序を持つ中間のモデルにする (SwiftData の配列リレーションは順序を保証しないため)。

| 属性 | 型 | 既定 | 意味 |
| --- | --- | --- | --- |
| `id` | `UUID` | `UUID()` | |
| `group` | `SnippetGroup?` | `nil` | |
| `snippet` | `Snippet?` | `nil` | スニペットの削除ルールは `.cascade` (スニペットを消すと項目も消える) |
| `sortIndex` | `Int` | `0` | メニューでの並び順 |

メニューの項目名はスニペットのタイトル (無ければ本文の 1 行目)。

### SnippetEmbedding (端末内)

意味検索のベクトル。本文から作り直せる派生データ。

| 属性 | 型 | 意味 |
| --- | --- | --- |
| `snippetID` | `UUID` | 対象の `Snippet.id` |
| `modelIdentifier` | `String` | ベクトルを作った埋め込みモデルとその版。一致しないベクトルは検索に使わず作り直す |
| `sourceHash` | `String` | ベクトルの元にしたテキストのハッシュ。スニペットの更新で一致しなくなったら作り直す |
| `vector` | `Data` | ベクトル |

### MCPClient (端末内)

MCP サーバーに接続を許可したクライアント。設定画面の一覧と接続の取り消しに使う。

| 属性 | 型 | 意味 |
| --- | --- | --- |
| `id` | `UUID` | |
| `name` | `String` | クライアント名 (Touch ID の確認画面・作成主体の表示に使う) |
| `createdAt` | `Date` | |
| `lastUsedAt` | `Date?` | |

トークンそのものは Keychain に置き、ストアには入れない。取り消しは Keychain のトークンとこのレコードを消す。

## 保存しないもの

- 購入状態 (ライセンス): 決済の仕組みが決まってから決める。Mac を直販、iOS を App Store の IAP で売る場合、一方で買ったライセンスをもう一方で有効にするかは未決定
- 本文の変更履歴・ゴミ箱: 要件に無い

## スキーマの版

`VersionedSchema` と `SchemaMigrationPlan` で版を管理する。最初の版を `SchemaV1` とし、モデルを変える時は新しい版と移行段階を足す。
