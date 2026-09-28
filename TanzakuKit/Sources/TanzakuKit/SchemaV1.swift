import Foundation
import SwiftData

/// 最初の版のスキーマ。属性の意味・既定値・削除ルールの正は `documents/data-model.md`。
///
/// 本番の CloudKit スキーマは追加しかできないため、この版のモデルは書き換えない。モデルを変える時は `SchemaV2` と移行段階を足す (`.claude/rules/data-model.md`)。
public enum SchemaV1: VersionedSchema {
  /// この版の番号。
  public static var versionIdentifier: Schema.Version {
    Schema.Version(1, 0, 0)
  }

  /// この版のすべてのモデル。
  public static var models: [any PersistentModel.Type] {
    syncedModels + localModels
  }

  /// 同期するストアに置くモデル。
  public static var syncedModels: [any PersistentModel.Type] {
    [Snippet.self, Folder.self, Tag.self, SnippetGroup.self, SnippetGroupItem.self]
  }

  /// 端末内のストアに置くモデル。
  public static var localModels: [any PersistentModel.Type] {
    [SnippetEmbedding.self, MCPClient.self]
  }

  /// 1 件のスニペット。
  @Model
  public final class Snippet {
    /// ストアをまたいだ参照・MCP のツールで使う識別子。
    public var id: UUID = UUID()
    /// 出力する本文。空の本文では保存させない (`validateSnippetBody(body:)`)。
    public var body: String = ""
    /// 表示名。無ければ本文の 1 行目を表示する。
    public var title: String?
    /// キーワード展開・ランチャーで一致させる略語。`SnippetGroup.keyword` と同じ名前空間で一意 (`validateKeywordIsUnique(keyword:ownerID:modelContext:)`)。
    public var keyword: String?
    /// シンタックスハイライトの言語。`nil` はプレーンテキスト。
    public var language: String?
    /// 色の raw value。`nil` は色なし。
    public var colorRawValue: String?
    /// 0〜1 個のフォルダ。
    public var folder: Folder?
    /// 0 個以上のタグ。
    public var tags: [Tag]? = []
    /// このスニペットを入れたスニペットグループの項目。スニペットを消すと項目も消える。
    @Relationship(deleteRule: .cascade, inverse: \SnippetGroupItem.snippet)
    public var groupItems: [SnippetGroupItem]? = []
    /// 作成日時。
    public var createdAt: Date = Date.now
    /// 更新日時。
    public var updatedAt: Date = Date.now
    /// 作成した主体の種類 (`user` / `mcp`)。
    public var createdByKind: String = "user"
    /// 更新した主体の種類 (`user` / `mcp`)。
    public var updatedByKind: String = "user"
    /// 作成した主体が `mcp` の時の MCP クライアント名。
    public var createdByClientName: String?
    /// 更新した主体が `mcp` の時の MCP クライアント名。
    public var updatedByClientName: String?

    /// 必須の属性は本文だけのため、本文だけを受け取る。
    public init(body: String) {
      self.body = body
    }
  }

  /// スニペットを入れるフォルダ。
  @Model
  public final class Folder {
    /// 識別子。
    public var id: UUID = UUID()
    /// フォルダ名。
    public var name: String = ""
    /// フォルダに入っているスニペット。フォルダを消してもスニペットは残る。
    @Relationship(deleteRule: .nullify, inverse: \Snippet.folder)
    public var snippets: [Snippet]? = []

    /// フォルダ名だけを受け取る。
    public init(name: String) {
      self.name = name
    }
  }

  /// スニペットに付けるタグ。
  @Model
  public final class Tag {
    /// 識別子。
    public var id: UUID = UUID()
    /// タグ名。
    public var name: String = ""
    /// タグを付けたスニペット。タグを消してもスニペットは残る。
    @Relationship(deleteRule: .nullify, inverse: \Snippet.tags)
    public var snippets: [Snippet]? = []

    /// タグ名だけを受け取る。
    public init(name: String) {
      self.name = name
    }
  }

  /// キーワードを打つと、登録したスニペットから 1 つを選ばせるメニューを出すまとまり。
  @Model
  public final class SnippetGroup {
    /// 識別子。
    public var id: UUID = UUID()
    /// 管理画面での表示名。
    public var name: String = ""
    /// メニューを出すキーワード。`Snippet.keyword` と同じ名前空間で一意。
    public var keyword: String?
    /// メニューに並ぶ項目。グループを消すと項目も消える。
    @Relationship(deleteRule: .cascade, inverse: \SnippetGroupItem.group)
    public var items: [SnippetGroupItem]? = []
    /// 作成日時。
    public var createdAt: Date = Date.now
    /// 更新日時。
    public var updatedAt: Date = Date.now

    /// 表示名だけを受け取る。
    public init(name: String) {
      self.name = name
    }
  }

  /// スニペットグループのメニューに並ぶ 1 項目。SwiftData の配列リレーションは順序を保証しないため、順序を持つ中間のモデルにする。
  @Model
  public final class SnippetGroupItem {
    /// 識別子。
    public var id: UUID = UUID()
    /// 項目が属するグループ。
    public var group: SnippetGroup?
    /// 項目が指すスニペット。
    public var snippet: Snippet?
    /// メニューでの並び順。
    public var sortIndex: Int = 0

    /// リレーションはストアに入れた後に張るため、並び順だけを受け取る。
    public init(sortIndex: Int) {
      self.sortIndex = sortIndex
    }
  }

  /// 意味検索のベクトル。本文から作り直せる派生データで、端末内のストアに置く。
  @Model
  public final class SnippetEmbedding {
    /// 対象の `Snippet.id`。ストア間はリレーションを張れないため識別子で参照する。
    public var snippetID: UUID
    /// ベクトルを作った埋め込みモデルとその版。一致しないベクトルは検索に使わず作り直す。
    public var modelIdentifier: String
    /// ベクトルの元にしたテキストのハッシュ。スニペットの更新で一致しなくなったら作り直す。
    public var sourceHash: String
    /// L2 正規化した `Float` の配列のバイト列。
    public var vector: Data

    /// すべての属性を受け取る。
    public init(snippetID: UUID, modelIdentifier: String, sourceHash: String, vector: Data) {
      self.snippetID = snippetID
      self.modelIdentifier = modelIdentifier
      self.sourceHash = sourceHash
      self.vector = vector
    }
  }

  /// MCP サーバーに接続を許可したクライアント。トークンそのものは Keychain に置き、ここには入れない。
  @Model
  public final class MCPClient {
    /// 識別子。
    public var id: UUID
    /// クライアント名 (Touch ID の確認画面・作成主体の表示に使う)。
    public var name: String
    /// 接続を許可した日時。
    public var createdAt: Date
    /// 最後に使った日時。
    public var lastUsedAt: Date?

    /// 接続を許可した時点の値を受け取る。
    public init(id: UUID, name: String, createdAt: Date) {
      self.id = id
      self.name = name
      self.createdAt = createdAt
    }
  }
}

/// 現在の版のスニペット。
public typealias Snippet = SchemaV1.Snippet
/// 現在の版のフォルダ。
public typealias Folder = SchemaV1.Folder
/// 現在の版のタグ。
public typealias Tag = SchemaV1.Tag
/// 現在の版のスニペットグループ。
public typealias SnippetGroup = SchemaV1.SnippetGroup
/// 現在の版のスニペットグループの項目。
public typealias SnippetGroupItem = SchemaV1.SnippetGroupItem
/// 現在の版の意味検索のベクトル。
public typealias SnippetEmbedding = SchemaV1.SnippetEmbedding
/// 現在の版の MCP クライアント。
public typealias MCPClient = SchemaV1.MCPClient
