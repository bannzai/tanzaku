# データモデル

スニペットの保存に使う SwiftData のモデルの仕様。要件と決定の経緯は `documents/DIRECTION.md` にあり、ここではそれを満たす保存の形だけを書く。変更時の規律は `.claude/rules/data-model.md`。

## 前提

- 保存は SwiftData。バックエンドは持たない
- macOS アプリと iOS アプリで同じモデルを使い、最初の版から iCloud (CloudKit) のプライベートデータベースで同期する
- macOS 版は Developer ID で配布する。Developer ID で署名したアプリも Developer ID 用の provisioning profile があれば CloudKit を使える ( https://developer.apple.com/developer-id/ )。リリースは `scripts/macos/install_developer_id_profile.rb` が用意する profile で署名する (`AGENTS.md`「Mac 版のリリース」)
- CI・simtunnel のビルドは iCloud の entitlement を外して署名し、同期せずに端末内だけで動く (`documents/DIRECTION.md`「決めたこと」)。ad-hoc 署名では iCloud の entitlement を満たす provisioning profile が無いため

## ストアの分け方

| ストア | 置くモデル | 同期 | 理由 |
| --- | --- | --- | --- |
| 同期するストア | `Snippet`・`Folder`・`Tag`・`SnippetGroup`・`SnippetGroupItem` | する (`ModelConfiguration` の `cloudKitDatabase: .automatic`。entitlement の iCloud コンテナ `iCloud.com.bannzai.tanzaku` のプライベートデータベースを使う。iCloud の entitlement を持たない拡張・CI のビルドでは同期しない) | ユーザーのデータで、どの端末でも同じであるべきもの |
| 端末内のストア | `SnippetEmbedding`・`MCPClient` | しない (`cloudKitDatabase: .none`) | 意味検索のベクトルは端末の OS・埋め込みモデルの版で変わり、同期すると別の版のベクトルが混ざる。MCP の接続先はその Mac の localhost サーバーに属し、iOS には無い |

iOS では、本体アプリ・共有シート・App Intents・カスタムキーボードが同じストアを使うため、ストアのファイルを App Group (`group.com.bannzai.tanzaku`) の共有コンテナに置く。後から場所を移すと既存ユーザーのデータの移行が要るため、最初の版から共有コンテナに置く。カスタムキーボードはフルアクセスが無い時に共有コンテナへ書き込めず、読むことはできる (Simulator での確かめと実機の扱いは `documents/DIRECTION.md`「決めたこと」)。キーボードからはストアへ書き込まない。

2 つの `ModelConfiguration` を 1 つの `ModelContainer` にまとめる。ストア間はリレーションを張れないため、端末内のストアからは `Snippet.id` (UUID) で参照する。

## CloudKit と両立させるための制約

同期するストアのモデルは次を守る (CloudKit の制約: https://developer.apple.com/documentation/coredata/creating-a-core-data-model-for-cloudkit 、 https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices )。

- すべての属性は Optional か既定値を持つ
- `@Attribute(.unique)` を使わない。一意であるべき値 (キーワード) はアプリのコードで保証する
- リレーションはすべて Optional。削除ルールに `.deny` を使わない
- 本番の CloudKit スキーマは追加しかできない。属性・モデルの削除や改名はせず、使わなくなった属性は残して読まない

## CloudKit のスキーマ

CloudKit のコンテナには開発 (Development) と本番 (Production) の 2 つの環境があり、アプリの `com.apple.developer.icloud-container-environment` の entitlement で決まる ( https://developer.apple.com/documentation/cloudkit/ckcontainer の「Testing Your Code Using the Development Container」。「Simulator works only with the development environment.」)。2026-10-19 に Simulator で Debug ビルドを動かした時の CloudKit のログは `containerIdentifier=iCloud.com.bannzai.tanzaku, environment=Sandbox` だった。`make macos` の Release ビルドは開発用の profile (Mac Team Provisioning Profile) で署名され、`com.apple.developer.icloud-container-environment` の entitlement を持たなかった (2026-10-19 に `codesign -d --entitlements -` で確認。起動はしていない)。開発用の profile のアプリは開発の環境を使う (同じ CKContainer の文書の「discover whether you're using a Development or Production version of your provisioning profile」)。Mac 版のリリースは export で `iCloudContainerEnvironment` を `Production` にし (`scripts/macos/build_notarized_dmg.sh`)、2026-10-19 に手元で export したアプリの署名の entitlement は `com.apple.developer.icloud-container-environment = Production` だった。

### 開発用のスキーマを初期化する

モデルを足した・変えた時は、本番へ反映する前に開発の環境のスキーマを作り直す。Apple の手順 ( https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices の「Initialize the CloudKit development schema」) は、SwiftData のストアと同じファイルを `NSPersistentCloudKitContainer` で開き `initializeCloudKitSchema()` を呼ぶ。この手順はコミットしない一時的な変更として行う (起動のたびに走らせない)。

1. iCloud にサインインした Simulator を `sim-boot` で起動する (simslim の `icloud` カテゴリを残す: `simslim on <udid> --except store,siri,icloud`)
2. `TanzakuiOS/TanzakuiOSApp.swift` の `init()` の先頭に、Apple の手順の `#if DEBUG` のブロックを一時的に入れる。`ModelConfiguration` は `makeTanzakuModelContainer` と同じ同期するストアの URL (App Group の共有コンテナの `Tanzaku/Synced.store`)、`NSPersistentCloudKitContainerOptions` のコンテナは `iCloud.com.bannzai.tanzaku`、`NSManagedObjectModel.makeManagedObjectModel(for:)` に渡す型は `SchemaV4.syncedModels` (同期するストアのモデルだけ。端末内のストアのモデルを CloudKit に作らない)
3. Debug 構成をチームの署名でビルドして起動する (`xcodebuild -scheme TanzakuiOS -configuration Debug -destination id=<udid> -allowProvisioningUpdates build` の後に `xcrun simctl install`・`xcrun simctl launch`)
4. CloudKit Console ( https://icloud.developer.apple.com ) の開発の環境で、`CD_Snippet`・`CD_Folder`・`CD_Tag`・`CD_SnippetGroup`・`CD_SnippetGroupItem` の record type ができたことを確かめる (Core Data は record type の名前に `CD_` を付ける: https://developer.apple.com/documentation/coredata/reading-cloudkit-records-for-core-data )
5. 2 の変更を戻す

### 本番へ反映する

CloudKit Console の「Deploy Schema Changes」で開発の環境のスキーマを本番へ反映する ( https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema )。本番の環境では record type・field を足せない (「The production server generates errors when your app tries to add record types or add new fields to existing record types.」 https://developer.apple.com/documentation/cloudkit/ckcontainer )。そのため、反映は公開前チェックリスト (#4) の項目にし、Mac 版の tag を打つ前に行う。コマンドラインの `xcrun cktool` は開発の環境 (sandbox) へのスキーマの取り込みまでで、本番への反映は Console で行う (「The CloudKit command line tools download, verify, and install a schema to your container's sandbox environment, while the CloudKit dashboard promotes a schema to the production environment.」 https://developer.apple.com/documentation/cloudkit/integrating-a-text-based-schema-into-your-workflow )。

## モデル

### Snippet

1 件のスニペット。

| 属性 | 型 | 既定 | 意味 |
| --- | --- | --- | --- |
| `id` | `UUID` | `UUID()` | ストアをまたいだ参照・MCP のツールで使う識別子 |
| `body` | `String` | `""` | 出力する本文。本文か添付のどちらかが必須 (本文も添付も無いスニペットは保存させない。アプリのコードで検査する)。添付のスニペットは空にする |
| `title` | `String?` | `nil` | 無ければ一覧・ランチャーで本文の 1 行目、本文も無ければ添付のファイル名を表示する |
| `keyword` | `String?` | `nil` | キーワード展開・ランチャーで一致させる略語。`SnippetGroup.keyword` と同じ名前空間で一意 |
| `language` | `String?` | `nil` | シンタックスハイライトの言語。よく使う言語は `SnippetLanguage` の raw value、それ以外は highlight.js の言語名 (`rust` など)。`nil` と、言語の Picker に並ばない値はプレーンテキスト |
| `colorRawValue` | `String?` | `nil` | 色 (朱・藍・松葉・山吹・紫) の raw value (`SnippetColor` の `shu` / `ai` / `matsuba` / `yamabuki` / `murasaki`)。`nil` と、これ以外の値は色なし |
| `folder` | `Folder?` | `nil` | 0〜1 個のフォルダ |
| `tags` | `[Tag]?` | `[]` | 0 個以上のタグ |
| `groupItems` | `[SnippetGroupItem]?` | `[]` | このスニペットを入れたスニペットグループの項目 (`SnippetGroupItem.snippet` の逆のリレーション)。削除ルールは `.cascade` (スニペットを消すと項目も消える)。CloudKit はリレーションに逆向きを求めるため置く |
| `createdAt` / `updatedAt` | `Date` | `.now` | |
| `createdByKind` / `updatedByKind` | `String` | `"user"` | 作成・更新した主体の種類 (`user` / `mcp`)。`#Predicate` で絞り込めるよう、Codable の複合型にせず平の属性にする |
| `createdByClientName` / `updatedByClientName` | `String?` | `nil` | 主体が `mcp` の時の MCP クライアント名 |
| `lastUsedAt` | `Date?` | `nil` | 最後に使った日時。Mac のランチャーでコピー・貼り付けした時、Mac のスニペットグループのメニューで選んだ時、iOS の一覧・詳細・ショートカット (App Intents) でコピーした時に更新する。iOS のキーボードで入れた時は更新しない (キーボードからはストアへ書き込まない)。使っても `updatedAt` と更新の主体は変えない。ランチャーの検索語が空の時に、新しい順に最大 10 件を出す。`SchemaV2` で足した |
| `attachmentData` | `Data?` | `nil` | 本文の代わりに出力する画像・動画 (添付) のデータ。`@Attribute(.externalStorage)` で大きなデータをストアの行の外のファイルに置き、行を読むたびに添付を読み込まないようにする。CloudKit との同期では、レコードの上限 1 MB に収まらない値を Core Data が Asset (CKAsset) に変えて送る (「If a field's value grows too large to store within the record size limit of 1MB, Core Data automatically converts the value to an external asset.」 https://developer.apple.com/documentation/coredata/reading-cloudkit-records-for-core-data )。大きさは 50,000,000 バイトまで (「Maximum file size of an Asset field: 50 MB」 https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/PropertyMetrics.html 。Apple が Asset の大きさの上限を数値で示している文書はこれだけで、CloudKit Web Services の文書。アプリのコードで検査する)。`SchemaV3` で足した |
| `attachmentContentType` | `String?` | `nil` | 添付の種類の UTType の識別子 (`public.png` など)。画像 (`public.image` に合うもの) と動画 (`public.movie` に合うもの) だけ。添付の有無はこの属性で判定し、データは読まない (データを読むと添付の全体をメモリに載せるため)。`SchemaV3` で足した |
| `attachmentFileName` | `String?` | `nil` | 添付のファイル名。添付がある時は必ず値を持つ (写真のライブラリから選んだ時など名前が無い時は、種類から `image.png`・`video.mov` のように作る)。クリップボードに入れるファイルの名前と、タイトルも本文も無い時の表示名に使う。`SchemaV3` で足した |
| `mcpApprovedContentHash` | `String?` | `nil` | ユーザーが内容を見た時 (設定の「AI エージェント」で承認した・編集画面で保存した) のキーワードと本文の SHA-256 (`snippetKeywordExpansionContentHash(snippet:)`)。MCP の `create_snippet` / `update_snippet` は `mcp-unapproved` (`snippetMCPUnapprovedContentHash`。どの内容のハッシュとも一致しない。空文字にしないのは同期の往復で `nil` と区別されるかを確かめていないため) にする。値があるスニペットは、更新した主体によらず、これが今のキーワードと本文のハッシュと一致しない間は承認待ちで、Mac のキーワード展開に使わない。真偽値や更新した主体で判断しないのは、別の端末の書き込み (MCP の本文・承認・ユーザーの保存) が同期で属性ごとに組み合わさっても、見ていない本文を承認済みにしないため。承認しても `updatedAt` と更新の主体は変えない。既定の `nil` はこの属性を足す前に保存したスニペットで、`updatedByKind` が `mcp` なら承認待ち、`user` ならそのまま展開する。`SchemaV4` で足した |

添付の 3 つの属性は、すべて値を持つ (添付のスニペット) か、すべて `nil` (本文のスニペット) のどちらかにする。iOS のキーボードは添付のスニペットを読み込みの条件 (`attachmentContentType == nil`) で外し、添付をメモリに載せない。

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

| 版 | 変えたこと | 前の版からの移行段階 |
| --- | --- | --- |
| `SchemaV1` | 最初の版 | |
| `SchemaV2` | `Snippet.lastUsedAt` を足した | lightweight (既存のスニペットの `lastUsedAt` は `nil` のまま) |
| `SchemaV3` | `Snippet.attachmentData`・`attachmentContentType`・`attachmentFileName` を足した | lightweight (既存のスニペットは本文のスニペットのまま。添付の 3 つの属性は `nil`) |
| `SchemaV4` (現在) | `Snippet.mcpApprovedContentHash` を足した | lightweight (既存のスニペットは `nil`。`updatedByKind` が `mcp` のスニペットは承認待ちになる) |
