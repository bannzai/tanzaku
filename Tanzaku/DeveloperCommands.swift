#if DEBUG
  import AppKit
  import SwiftData
  import SwiftUI
  import TanzakuKit
  import os

  /// 開発者メニューの操作の失敗の記録。開発者メニューは画面の確認で状態を作るための Debug ビルドだけの操作で、失敗してもアプリを落とさず記録だけにする。スニペットの本文は入れない (`.claude/rules/snippet-content-handling.md`)。
  private let developerCommandsLogger = Logger(subsystem: "com.bannzai.tanzaku", category: "DeveloperCommands")

  /// スニペット・フォルダ・タグ・意味検索のベクトルをすべて消して保存する。
  ///
  /// 1 件ずつ消す。`ModelContext.delete(model:)` の一括削除はリレーション (スニペットとタグの多対多など) の削除ルールを通さず、simtunnel で押すとアプリが落ちたため (落ちた箇所のログは取れていない)。消す対象が無ければ何もせず、何度呼んでも結果は同じになる。
  func deleteAllSnippetData(modelContext: ModelContext) throws {
    for snippet in try modelContext.fetch(FetchDescriptor<Snippet>()) {
      modelContext.delete(snippet)
    }
    for folder in try modelContext.fetch(FetchDescriptor<Folder>()) {
      modelContext.delete(folder)
    }
    for tag in try modelContext.fetch(FetchDescriptor<Tag>()) {
      modelContext.delete(tag)
    }
    for snippetEmbedding in try modelContext.fetch(FetchDescriptor<SnippetEmbedding>()) {
      modelContext.delete(snippetEmbedding)
    }
    try modelContext.save()
  }

  /// 開発者メニューが入れる見本のスニペット 1 件の定義。本文は画面の確認で撮影して公開するため、明らかに偽の値にする (`.claude/rules/snippet-content-handling.md`)。
  struct DeveloperSampleSnippet {
    /// キーワード。同じキーワードのスニペットがあれば入れない (キーワードはスニペットの間で一意)。
    let keyword: String
    /// 表示名。
    let title: String
    /// 本文。「Delete Sample Data」はこの本文と一致するスニペットを見本とみなす。
    let body: String
    /// 色。
    let color: SnippetColor
    /// シンタックスハイライトの言語。
    let language: SnippetLanguage?
    /// 入れるフォルダの名前。同じ名前のフォルダがあればそれを使う。
    let folderName: String?
    /// 付けるタグの名前。同じ名前のタグがあればそれを使う。
    let tagNames: [String]
    /// 更新日時を今から何秒前にするか。一覧は更新日時の新しい順に並ぶため、デザインの並びになるようずらす。
    let updatedSecondsAgo: TimeInterval
  }

  /// 「Insert Sample Snippets」の見本。デザイン (`documents/design/Main.dc.html`) の例と同じにする。
  let launcherSampleSnippets = [
    DeveloperSampleSnippet(
      keyword: "envkey",
      title: "環境変数からトークンを取得",
      body: "# API_TOKEN が未設定ならダミー値で進める\nexport API_TOKEN=\"${API_TOKEN:-dummy-token}\"\n\ncurl -sS \\\n  -H \"Authorization: Bearer ${API_TOKEN}\" \\\n  https://api.example.com/v1/me",
      color: .shu,
      language: nil,
      folderName: "開発環境",
      tagNames: ["shell", "auth"],
      updatedSecondsAgo: 0
    ),
    DeveloperSampleSnippet(
      keyword: "envrc",
      title: ".envrc の雛形",
      body: "export API_TOKEN=dummy-token",
      color: .matsuba,
      language: nil,
      folderName: nil,
      tagNames: [],
      updatedSecondsAgo: 60
    ),
    DeveloperSampleSnippet(
      keyword: "ghsec",
      title: "GitHub Actions の secrets 参照",
      body: "- run: ./scripts/deploy.sh\n  with:\n    token: ${{ secrets.DEPLOY_TOKEN }}",
      color: .ai,
      language: nil,
      folderName: nil,
      tagNames: [],
      updatedSecondsAgo: 120
    ),
  ]

  /// 「Insert Manager Sample Data」の見本。デザイン (`documents/design/Manager.dc.html`) と同じ並びにする。
  let managerSampleSnippets = [
    DeveloperSampleSnippet(
      keyword: "envkey",
      title: "環境変数からトークンを取得",
      body: "export API_TOKEN=\"${API_TOKEN:-dummy-token}\"",
      color: .shu,
      language: .shell,
      folderName: "開発環境",
      tagNames: ["shell"],
      updatedSecondsAgo: 2 * 24 * 60 * 60
    ),
    DeveloperSampleSnippet(
      keyword: "envrc",
      title: ".envrc の雛形",
      body: "export API_TOKEN=dummy-token\nexport API_BASE_URL=https://example.com",
      color: .matsuba,
      language: .shell,
      folderName: "開発環境",
      tagNames: ["shell"],
      updatedSecondsAgo: 4 * 24 * 60 * 60
    ),
    DeveloperSampleSnippet(
      keyword: "ghsec",
      title: "GitHub Actions の secrets 参照",
      body:
        "jobs:\n  deploy:\n    runs-on: ubuntu-latest\n    env:\n      API_TOKEN: ${{ secrets.API_TOKEN }}\n      DEPLOY_KEY: ${{ secrets.DEPLOY_KEY }}\n    steps:\n      - uses: actions/checkout@v4\n      - run: ./scripts/deploy.sh",
      color: .ai,
      language: .yaml,
      folderName: "GitHub",
      tagNames: ["github-actions", "ci"],
      updatedSecondsAgo: 1 * 24 * 60 * 60
    ),
    DeveloperSampleSnippet(
      keyword: "prrev",
      title: "PR レビュー依頼の文面",
      body: "レビューをお願いします。変更の目的は次のとおりです。",
      color: .yamabuki,
      language: nil,
      folderName: "文面",
      tagNames: ["review"],
      updatedSecondsAgo: 6 * 24 * 60 * 60
    ),
    DeveloperSampleSnippet(
      keyword: "research",
      title: "Claude に渡す調査の指示",
      body: "次の件を調査して、結論から報告してください。",
      color: .murasaki,
      language: nil,
      folderName: "AI プロンプト",
      tagNames: ["claude"],
      updatedSecondsAgo: 7 * 24 * 60 * 60
    ),
  ]

  /// 「Show Sample Deletion Request」で削除の依頼を出す見本。内容はデザイン (`documents/design/AgentDelete.dc.html`) の見本に合わせる。
  ///
  /// キーワード `envrc` は他の見本も使うため、使われていない時だけ付ける (`insertDeletionRequestSampleSnippet(modelContext:now:)`)。
  let deletionRequestSampleSnippet = DeveloperSampleSnippet(
    keyword: "envrc",
    title: String(localized: ".envrc template"),
    body: "export API_TOKEN=dummy-token-for-test\nexport DATABASE_URL=postgres://localhost:5432/app_dev\nexport LOG_LEVEL=debug\n\ndotenv_if_exists .env.local",
    color: .matsuba,
    language: nil,
    folderName: String(localized: "Dev environment"),
    tagNames: ["shell", "direnv"],
    updatedSecondsAgo: 0
  )

  /// 「Insert Manager Sample Data」で入れるスニペットグループの名前。「Delete Sample Data」は名前とキーワードの両方が一致するグループを見本とみなす。
  let managerSampleSnippetGroupName = "開発環境のセットアップ"
  /// 「Insert Manager Sample Data」で入れるスニペットグループのキーワード。
  let managerSampleSnippetGroupKeyword = ";dev-env"

  /// 名前が一致するフォルダを返し、無ければ作る。見本を何度入れても同じ名前のフォルダを増やさないため。
  func developerSampleFolder(name: String, modelContext: ModelContext) throws -> Folder {
    if let folder = try modelContext.fetch(FetchDescriptor<Folder>(predicate: #Predicate { $0.name == name })).first {
      return folder
    }
    let folder = Folder(name: name)
    modelContext.insert(folder)
    return folder
  }

  /// キーワードがスニペットかスニペットグループで使われているか。見本のキーワードが既に使われている時に、見本を入れずに飛ばすため。
  ///
  /// キーワードの名前空間の検査は `validateKeywordIsUnique` を正とし、同じ条件で判定する。どのモデルにも属さない新しい `ownerID` を渡し、自分自身との一致を除かない。
  func isDeveloperSampleKeywordUsed(keyword: String, modelContext: ModelContext) throws -> Bool {
    do {
      try validateKeywordIsUnique(keyword: keyword, ownerID: UUID(), modelContext: modelContext)
      return false
    } catch SnippetValidationError.keywordAlreadyUsed {
      return true
    }
  }

  /// 見本のスニペットを入れる。保存は呼び出し側で行う。
  ///
  /// 同じキーワードのスニペット・スニペットグループがあれば入れず、同じ名前のフォルダ・タグがあればそれを使う (タグは `applySnippetEdit` が名前で使い回す) ため、何度呼んでもスニペット・フォルダ・タグは増えない。
  /// - Returns: 新しく入れたスニペットをキーワードで引ける辞書。
  func insertDeveloperSampleSnippets(sampleSnippets: [DeveloperSampleSnippet], modelContext: ModelContext, now: Date) throws -> [String: Snippet] {
    var insertedSnippetsByKeyword: [String: Snippet] = [:]
    for sampleSnippet in sampleSnippets {
      guard try !isDeveloperSampleKeywordUsed(keyword: sampleSnippet.keyword, modelContext: modelContext) else {
        continue
      }
      let snippet = Snippet(body: "")
      try applySnippetEdit(
        snippet: snippet,
        body: sampleSnippet.body,
        title: sampleSnippet.title,
        keyword: sampleSnippet.keyword,
        language: sampleSnippet.language?.rawValue,
        color: sampleSnippet.color,
        folder: try sampleSnippet.folderName.map { try developerSampleFolder(name: $0, modelContext: modelContext) },
        tagNames: sampleSnippet.tagNames,
        modelContext: modelContext,
        now: now.addingTimeInterval(-sampleSnippet.updatedSecondsAgo)
      )
      insertedSnippetsByKeyword[sampleSnippet.keyword] = snippet
    }
    return insertedSnippetsByKeyword
  }

  /// `operation` で変えたストアを保存する。失敗したら保存していない変更を捨ててから投げ直す。
  ///
  /// 開発者メニューはアプリと同じ `mainContext` を使うため、途中まで入れた見本・消した見本を残すと、後の別の保存で一緒に保存されてしまうため。
  func saveDeveloperSampleDataChanges(modelContext: ModelContext, operation: () throws -> Void) throws {
    do {
      try operation()
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
  }

  /// 「Insert Sample Snippets」の見本を入れて保存する。何度呼んでも同じ結果になる (`insertDeveloperSampleSnippets(sampleSnippets:modelContext:now:)`)。
  func insertLauncherSampleData(modelContext: ModelContext, now: Date) throws {
    try saveDeveloperSampleDataChanges(modelContext: modelContext) {
      _ = try insertDeveloperSampleSnippets(sampleSnippets: launcherSampleSnippets, modelContext: modelContext, now: now)
    }
  }

  /// デザイン (`documents/design/Manager.dc.html`) と同じ並びのスニペット・フォルダ・タグ・スニペットグループを入れて保存する。
  ///
  /// 同じキーワードのスニペット・スニペットグループがあれば入れないため、何度呼んでも同じ結果になる。「Insert Sample Snippets」で入れた見本と同じキーワードのスニペットは、その見本をそのまま使う。
  func insertManagerSampleData(modelContext: ModelContext, now: Date) throws {
    try saveDeveloperSampleDataChanges(modelContext: modelContext) {
      let insertedSnippetsByKeyword = try insertDeveloperSampleSnippets(sampleSnippets: managerSampleSnippets, modelContext: modelContext, now: now)
      for snippet in insertedSnippetsByKeyword.values {
        // 作成日時と更新日時が違うスニペットの表示を確かめるため、作成日時を更新日時より前にする。
        snippet.createdAt = snippet.updatedAt.addingTimeInterval(-7 * 24 * 60 * 60)
      }
      // MCP で変更した主体の表示を確かめるため。
      insertedSnippetsByKeyword["research"]?.createdByKind = "mcp"
      insertedSnippetsByKeyword["research"]?.createdByClientName = "Claude Code"
      insertedSnippetsByKeyword["research"]?.updatedByKind = "mcp"
      insertedSnippetsByKeyword["research"]?.updatedByClientName = "Claude Code"
      insertedSnippetsByKeyword["ghsec"]?.updatedByKind = "mcp"
      insertedSnippetsByKeyword["ghsec"]?.updatedByClientName = "Claude Code"
      let sampleGroupKeyword: String? = managerSampleSnippetGroupKeyword
      if try modelContext.fetchCount(FetchDescriptor<SnippetGroup>(predicate: #Predicate { $0.keyword == sampleGroupKeyword })) == 0 {
        let snippetsByKeyword = Dictionary(
          try modelContext.fetch(FetchDescriptor<Snippet>()).compactMap { snippet in snippet.keyword.map { ($0, snippet) } },
          uniquingKeysWith: { first, _ in first }
        )
        try applySnippetGroupEdit(
          snippetGroup: SnippetGroup(name: ""),
          name: managerSampleSnippetGroupName,
          keyword: managerSampleSnippetGroupKeyword,
          snippets: ["envkey", "envrc", "ghsec"].compactMap { snippetsByKeyword[$0] },
          modelContext: modelContext,
          now: now
        )
      }
    }
  }

  /// 削除の依頼に出す見本のスニペットを返す。保存は呼び出し側で行う。
  ///
  /// 前に入れた見本 (本文が一致するスニペット) が残っていればそれを使い、無ければ入れる。フォルダ・タグも同じ名前のものを使うため、何度押しても見本・フォルダ・タグは増えない。
  func insertDeletionRequestSampleSnippet(modelContext: ModelContext, now: Date) throws -> Snippet {
    let sampleBody = deletionRequestSampleSnippet.body
    if let snippet = try modelContext.fetch(FetchDescriptor<Snippet>(predicate: #Predicate { $0.body == sampleBody })).first {
      return snippet
    }
    let snippet = Snippet(body: "")
    try applySnippetEdit(
      snippet: snippet,
      body: deletionRequestSampleSnippet.body,
      title: deletionRequestSampleSnippet.title,
      keyword: try isDeveloperSampleKeywordUsed(keyword: deletionRequestSampleSnippet.keyword, modelContext: modelContext) ? "" : deletionRequestSampleSnippet.keyword,
      language: deletionRequestSampleSnippet.language?.rawValue,
      color: deletionRequestSampleSnippet.color,
      folder: try deletionRequestSampleSnippet.folderName.map { try developerSampleFolder(name: $0, modelContext: modelContext) },
      tagNames: deletionRequestSampleSnippet.tagNames,
      modelContext: modelContext,
      now: now
    )
    return snippet
  }

  /// 開発者メニューが入れた見本を消して保存する。ユーザーが作ったスニペット・スニペットグループ・フォルダ・タグは残す。
  ///
  /// 見本の印になる属性をモデルに足すと本番の CloudKit スキーマから消せなくなるため (`.claude/rules/data-model.md`)、見本は固定の値で見分ける。
  /// スニペットは見本の本文と一致するもの、スニペットグループは見本と名前・キーワードが一致するもの、フォルダ・タグは見本と同じ名前で見本のスニペットの他にスニペットが入っていないものを消す。
  /// 見本と同じ名前でもユーザーのスニペットが入ったフォルダ・タグは残し、スニペットが 1 つも無ければユーザーが作ったものでも消す (見本と見分けられないため)。
  /// `deleteAllSnippetData(modelContext:)` と同じ理由で 1 件ずつ消す。意味検索のベクトルは `updateSnippetEmbeddings` が消えたスニペットの分を消すため、ここでは消さない。消す対象が無ければ何もせず、何度呼んでも結果は同じになる。
  func deleteDeveloperSampleData(modelContext: ModelContext) throws {
    let allSampleSnippets = launcherSampleSnippets + managerSampleSnippets + [deletionRequestSampleSnippet]
    let sampleSnippetBodies = Set(allSampleSnippets.map(\.body))
    let sampleSnippets = try modelContext.fetch(FetchDescriptor<Snippet>()).filter { sampleSnippetBodies.contains($0.body) }
    let sampleSnippetIDs = Set(sampleSnippets.map(\.id))
    let sampleFolderNames = Set(allSampleSnippets.compactMap(\.folderName))
    let sampleFolders = try modelContext.fetch(FetchDescriptor<Folder>()).filter { folder in
      sampleFolderNames.contains(folder.name) && (folder.snippets ?? []).allSatisfy { sampleSnippetIDs.contains($0.id) }
    }
    let sampleTagNames = Set(allSampleSnippets.flatMap(\.tagNames))
    let sampleTags = try modelContext.fetch(FetchDescriptor<Tag>()).filter { tag in
      sampleTagNames.contains(tag.name) && (tag.snippets ?? []).allSatisfy { sampleSnippetIDs.contains($0.id) }
    }
    let sampleGroupKeyword: String? = managerSampleSnippetGroupKeyword
    let sampleSnippetGroups = try modelContext.fetch(FetchDescriptor<SnippetGroup>(predicate: #Predicate { $0.keyword == sampleGroupKeyword }))
      .filter { $0.name == managerSampleSnippetGroupName }
    try saveDeveloperSampleDataChanges(modelContext: modelContext) {
      for snippet in sampleSnippets {
        modelContext.delete(snippet)
      }
      for folder in sampleFolders {
        modelContext.delete(folder)
      }
      for tag in sampleTags {
        modelContext.delete(tag)
      }
      for snippetGroup in sampleSnippetGroups {
        modelContext.delete(snippetGroup)
      }
    }
  }

  /// Debug ビルドだけに出す開発者メニュー。simtunnel の画面の確認で、スニペットがある状態・無い状態とライト・ダークを作るため (`AGENTS.md`「画面の確認」)。
  ///
  /// 開発者向けの操作で翻訳しないため、文言は `Text(verbatim:)` にする。
  struct DeveloperCommands: Commands {
    /// ランチャーとストアを持つアプリの delegate。
    let appDelegate: AppDelegate

    var body: some Commands {
      CommandMenu(Text(verbatim: "Developer")) {
        Button {
          appDelegate.launcherPanelController?.show()
        } label: {
          Text(verbatim: "Open Launcher")
        }
        Divider()
        Button {
          do {
            try insertLauncherSampleData(modelContext: try appDelegate.modelContainerResult.get().mainContext, now: .now)
          } catch {
            developerCommandsLogger.error("Failed to insert sample snippets: \(String(describing: error), privacy: .public)")
          }
        } label: {
          Text(verbatim: "Insert Sample Snippets")
        }
        Button {
          do {
            try insertManagerSampleData(modelContext: try appDelegate.modelContainerResult.get().mainContext, now: .now)
          } catch {
            developerCommandsLogger.error("Failed to insert manager sample data: \(String(describing: error), privacy: .public)")
          }
        } label: {
          Text(verbatim: "Insert Manager Sample Data")
        }
        Button {
          do {
            try deleteDeveloperSampleData(modelContext: try appDelegate.modelContainerResult.get().mainContext)
          } catch {
            developerCommandsLogger.error("Failed to delete sample data: \(String(describing: error), privacy: .public)")
          }
        } label: {
          Text(verbatim: "Delete Sample Data")
        }
        Button {
          appDelegate.launcherPanelController?.deleteAllSnippets()
        } label: {
          Text(verbatim: "Delete All Snippets")
        }
        Divider()
        // simtunnel のランナーでは入力監視・アクセシビリティの許可を与えられず、キーワードを打ってもメニューが出ないため、メニューの見た目をここから確かめる。
        Button {
          appDelegate.snippetGroupMenuController?.toggleSampleSnippetGroupMenu()
        } label: {
          Text(verbatim: "Toggle Snippet Group Menu")
        }
        Divider()
        // MCP のクライアントを実際に接続しなくても、設定の「AI エージェント」と削除の確認の画面を確かめられるようにするため。
        Button {
          do {
            try addSampleMCPClients(modelContext: try appDelegate.modelContainerResult.get().mainContext, now: .now)
          } catch {
            developerCommandsLogger.error("Failed to add sample MCP clients: \(String(describing: error), privacy: .public)")
          }
        } label: {
          Text(verbatim: "Add Sample MCP Clients")
        }
        Button {
          guard let mcpServerController = appDelegate.mcpServerController else {
            return
          }
          Task {
            await showSampleDeletionRequest(controller: mcpServerController)
          }
        } label: {
          Text(verbatim: "Show Sample Deletion Request")
        }
        Divider()
        // 初回起動は終えると次の起動から出ないため、simtunnel で 3 つの手順を撮り直せるようにする。
        Button {
          appDelegate.showOnboardingWindow()
        } label: {
          Text(verbatim: "Show Onboarding")
        }
        Divider()
        Button {
          NSApp.appearance = NSAppearance(named: .aqua)
        } label: {
          Text(verbatim: "Appearance: Light")
        }
        Button {
          NSApp.appearance = NSAppearance(named: .darkAqua)
        } label: {
          Text(verbatim: "Appearance: Dark")
        }
        Button {
          NSApp.appearance = nil
        } label: {
          Text(verbatim: "Appearance: System")
        }
      }
    }
  }

  extension LauncherPanelController {
    /// スニペット・フォルダ・タグをすべて消す。どの入力でも結果なしの画面を出すため (意味検索の類似度の下限 0.65 を超える英語の入力は、関係が無くても意味が近い欄に出る。`documents/DIRECTION.md`「決めたこと」)。
    func deleteAllSnippets() {
      do {
        try deleteAllSnippetData(modelContext: modelContainer.mainContext)
      } catch {
        developerCommandsLogger.error("Failed to delete snippets: \(String(describing: error), privacy: .public)")
      }
    }
  }

  extension SnippetGroupMenuController {
    /// メニューを開いていれば閉じ、閉じていればキーワードとスニペットを持つスニペットグループのメニューをキー入力の監視を通さずに開く。「Insert Manager Sample Data」で入れた `;dev-env` があればそれを開く。
    ///
    /// キー入力の監視が動いていない時は ↑↓・Return・Esc を受け取れないため、閉じるのもこの操作で行う。開くグループが無ければ何もしない。
    func toggleSampleSnippetGroupMenu() {
      if isMenuOpen {
        closeMenu()
        return
      }
      do {
        let snippetGroups = try modelContainer.mainContext.fetch(FetchDescriptor<SnippetGroup>(predicate: #Predicate { $0.keyword != nil }))
          .filter { !snippetGroupMenuSnippets(snippetGroup: $0).isEmpty }
        if let snippetGroup = snippetGroups.first(where: { $0.keyword == managerSampleSnippetGroupKeyword }) ?? snippetGroups.first {
          openMenu(snippetGroup: snippetGroup)
        }
      } catch {
        developerCommandsLogger.error("Failed to fetch snippet groups: \(String(describing: error), privacy: .public)")
      }
    }
  }

  /// 接続済みのクライアントの見本を入れる。名前と最後のアクセスはデザイン (`documents/design/Settings.dc.html`) の見本に合わせる。
  ///
  /// 押すたびにクライアントが増える (冪等ではない)。取り消しの操作を何度でも確かめられるようにするため。
  func addSampleMCPClients(modelContext: ModelContext, now: Date) throws {
    for (name, lastUsedAt) in [
      ("Claude Code", now.addingTimeInterval(-2 * 60)),
      ("Claude Desktop", now.addingTimeInterval(-24 * 60 * 60)),
      ("Codex CLI", now.addingTimeInterval(-7 * 24 * 60 * 60)),
    ] {
      let client = MCPClient(id: UUID(), name: name, createdAt: lastUsedAt)
      client.lastUsedAt = lastUsedAt
      modelContext.insert(client)
    }
    try modelContext.save()
  }

  /// 見本のスニペット (`deletionRequestSampleSnippet`) を入れ、その削除の依頼を確認の画面に出す。許可されたら見本を消す。
  func showSampleDeletionRequest(controller: MCPServerController) async {
    let modelContext = controller.modelContainer.mainContext
    let snippet: Snippet
    do {
      snippet = try insertDeletionRequestSampleSnippet(modelContext: modelContext, now: .now)
      try modelContext.save()
    } catch {
      modelContext.rollback()
      developerCommandsLogger.error("Failed to insert the sample snippet to delete: \(String(describing: error), privacy: .public)")
      return
    }
    let isApproved = await controller.confirmSnippetDeletion(
      request: SnippetDeletionRequest(
        // 見本の依頼はどの接続済みのクライアントにも属さないため、取り消しで拒否されない新しい識別子にする。
        clientID: UUID(),
        rpcRequestID: "sample",
        clientName: "Claude Code",
        reason: String(localized: "direnv is no longer used, so this template is not needed anymore."),
        snippet: snippet,
        receivedAt: .now
      )
    )
    guard isApproved else {
      return
    }
    modelContext.delete(snippet)
    do {
      try modelContext.save()
    } catch {
      developerCommandsLogger.error("Failed to delete the sample snippet: \(String(describing: error), privacy: .public)")
    }
  }
#endif
