# データモデル

スニペットの保存に使う SwiftData のモデルの仕様。要件と決定の経緯は `documents/DIRECTION.md` にあり、ここではそれを満たす保存の形だけを書く。変更時の規律は `.claude/rules/data-model.md`。

## 前提

- 保存は SwiftData。バックエンドは持たない
- macOS アプリと iOS アプリで同じモデルを使い、最初の版から iCloud (CloudKit) のプライベートデータベースで同期する
- macOS 版は Developer ID で配布する。Developer ID で署名したアプリも Developer ID 用の provisioning profile があれば CloudKit を使える ( https://developer.apple.com/developer-id/ )。CI の ad-hoc 署名では iCloud の entitlement を満たす provisioning profile が無いため、CI でのビルドの署名の扱いは同期を実装する issue で決める

## ストアの分け方

| ストア | 置くモデル | 同期 | 理由 |
| --- | --- | --- | --- |
| 同期するストア | `Snippet`・`Folder`・`Tag`・`SnippetGroup`・`SnippetGroupItem` | する (`ModelConfiguration` の `cloudKitDatabase: .private(<コンテナ ID>)`) | ユーザーのデータで、どの端末でも同じであるべきもの |
| 端末内のストア | `SnippetEmbedding`・`MCPClient` | しない (`cloudKitDatabase: .none`) | 意味検索のベクトルは端末の OS・埋め込みモデルの版で変わり、同期すると別の版のベクトルが混ざる。MCP の接続先はその Mac の localhost サーバーに属し、iOS には無い |

iOS では、本体アプリ・共有シート・App Intents・カスタムキーボードが同じストアを使うため、ストアのファイルを App Group (`group.com.bannzai.tanzaku`) の共有コンテナに置く。後から場所を移すと既存ユーザーのデータの移行が要るため、最初の版から共有コンテナに置く。カスタムキーボードはフルアクセスが無い時に共有コンテナへ書き込めず、読むことはできる (Simulator での確かめと実機の扱いは `documents/DIRECTION.md`「決めたこと」)。キーボードからはストアへ書き込まない。

2 つの `ModelConfiguration` を 1 つの `ModelContainer` にまとめる。ストア間はリレーションを張れないため、端末内のストアからは `Snippet.id` (UUID) で参照する。

## CloudKit と両立させるための制約

同期するストアのモデルは次を守る (CloudKit の制約: https://developer.apple.com/documentation/coredata/creating-a-core-data-model-for-cloudkit 、 https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices )。

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
| `language` | `String?` | `nil` | シンタックスハイライトの言語。よく使う言語は `SnippetLanguage` の raw value、それ以外は highlight.js の言語名 (`rust` など)。`nil` と、言語の Picker に並ばない値はプレーンテキスト |
| `colorRawValue` | `String?` | `nil` | 色 (朱・藍・松葉・山吹・紫) の raw value (`SnippetColor` の `shu` / `ai` / `matsuba` / `yamabuki` / `murasaki`)。`nil` と、これ以外の値は色なし |
| `folder` | `Folder?` | `nil` | 0〜1 個のフォルダ |
| `tags` | `[Tag]?` | `[]` | 0 個以上のタグ |
| `groupItems` | `[SnippetGroupItem]?` | `[]` | このスニペットを入れたスニペットグループの項目 (`SnippetGroupItem.snippet` の逆のリレーション)。削除ルールは `.cascade` (スニペットを消すと項目も消える)。CloudKit はリレーションに逆向きを求めるため置く |
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
| `snippet` | `Snippet?` | `nil` | スニペットの削除ルールは `.cascade` (スニペットを消すと項目も消える。`Snippet.groupItems` に置く) |
| `sortIndex` | `Int` | `0` | メニューでの並び順 |

メニューの項目名はスニペットのタイトル (無ければ本文の 1 行目)。

### SnippetEmbedding (端末内)

意味検索のベクトル。本文から作り直せる派生データ。

| 属性 | 型 | 意味 |
| --- | --- | --- |
| `snippetID` | `UUID` | 対象の `Snippet.id` |
| `modelIdentifier` | `String` | ベクトルを作った埋め込みモデルとその版。一致しないベクトルは検索に使わず作り直す |
| `sourceHash` | `String` | ベクトルの元にしたテキスト (キーワード・タイトル・本文) の SHA-256。スニペットの更新で一致しなくなったら作り直す |
| `vector` | `Data` | 長さ 1 に正規化した `Float` の配列のバイト列 |

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

- 購入状態 (ライセンス): SwiftData にも CloudKit にも置かない。Mac は Lemon Squeezy のライセンスキーを Keychain に置き、iOS は StoreKit の購入履歴を正とする。Mac で買ったライセンスを iOS で有効にするか (逆も) は未決定。iOS で認める場合も、同じ機能を IAP で買えるようにする必要がある (Guideline 3.1.3(b) Multiplatform Services)
- 本文の変更履歴・ゴミ箱: 要件に無い

## スキーマの版

`VersionedSchema` と `SchemaMigrationPlan` で版を管理する。最初の版を `SchemaV1` とし、モデルを変える時は新しい版と移行段階を足す。
