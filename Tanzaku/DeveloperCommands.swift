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

  /// デザイン (`documents/design/Manager.dc.html`) と同じ並びのスニペット・フォルダ・タグ・スニペットグループを入れる。
  ///
  /// 本文は明らかに偽の値にする (`.claude/rules/snippet-content-handling.md`)。見本のキーワード `envkey` のスニペットが既にあれば (「Insert Sample Snippets」で入れた時を含む) 何もしないため、何度呼んでも同じ結果になる。
  func insertManagerSampleData(modelContext: ModelContext, now: Date) throws {
    let sampleKeyword: String? = "envkey"
    guard try modelContext.fetchCount(FetchDescriptor<Snippet>(predicate: #Predicate { $0.keyword == sampleKeyword })) == 0 else {
      return
    }
    let calendar = Calendar.current
    let foldersByName = Dictionary(
      uniqueKeysWithValues: ["開発環境", "GitHub", "文面", "AI プロンプト"].map { name in
        let folder = Folder(name: name)
        modelContext.insert(folder)
        return (name, folder)
      }
    )
    let tagsByName = Dictionary(
      uniqueKeysWithValues: ["shell", "github-actions", "ci", "review", "claude"].map { name in
        let tag = Tag(name: name)
        modelContext.insert(tag)
        return (name, tag)
      }
    )
    let samples: [(title: String, body: String, keyword: String, color: SnippetColor, language: SnippetLanguage?, folderName: String, tagNames: [String], daysAgo: Int)] = [
      ("環境変数からトークンを取得", "export API_TOKEN=\"${API_TOKEN:-dummy-token}\"", "envkey", .shu, .shell, "開発環境", ["shell"], 2),
      (".envrc の雛形", "export API_TOKEN=dummy-token\nexport API_BASE_URL=https://example.com", "envrc", .matsuba, .shell, "開発環境", ["shell"], 4),
      (
        "GitHub Actions の secrets 参照",
        "jobs:\n  deploy:\n    runs-on: ubuntu-latest\n    env:\n      API_TOKEN: ${{ secrets.API_TOKEN }}\n      DEPLOY_KEY: ${{ secrets.DEPLOY_KEY }}\n    steps:\n      - uses: actions/checkout@v4\n      - run: ./scripts/deploy.sh",
        "ghsec", .ai, .yaml, "GitHub", ["github-actions", "ci"], 1
      ),
      ("PR レビュー依頼の文面", "レビューをお願いします。変更の目的は次のとおりです。", "prrev", .yamabuki, nil, "文面", ["review"], 6),
      ("Claude に渡す調査の指示", "次の件を調査して、結論から報告してください。", "research", .murasaki, nil, "AI プロンプト", ["claude"], 7),
    ]
    let snippetsByKeyword = Dictionary(
      uniqueKeysWithValues: samples.map { sample in
        let snippet = Snippet(body: sample.body)
        modelContext.insert(snippet)
        snippet.title = sample.title
        snippet.keyword = sample.keyword
        snippet.colorRawValue = sample.color.rawValue
        snippet.language = sample.language?.rawValue
        snippet.folder = foldersByName[sample.folderName]
        snippet.tags = sample.tagNames.compactMap { tagsByName[$0] }
        snippet.createdAt = calendar.date(byAdding: .day, value: -sample.daysAgo - 7, to: now) ?? now
        snippet.updatedAt = calendar.date(byAdding: .day, value: -sample.daysAgo, to: now) ?? now
        return (sample.keyword, snippet)
      }
    )
    // 「AI エージェントが追加」の絞り込みと、MCP で変更した主体の表示を確かめるため。
    snippetsByKeyword["research"]?.createdByKind = "mcp"
    snippetsByKeyword["research"]?.createdByClientName = "Claude Code"
    snippetsByKeyword["research"]?.updatedByKind = "mcp"
    snippetsByKeyword["research"]?.updatedByClientName = "Claude Code"
    snippetsByKeyword["ghsec"]?.updatedByKind = "mcp"
    snippetsByKeyword["ghsec"]?.updatedByClientName = "Claude Code"
    // 「Delete All Snippets」はスニペットグループを消さないため、前に入れたグループが残っていれば作らない (同じキーワードのグループは作れない)。
    let sampleGroupKeyword: String? = ";dev-env"
    if try modelContext.fetchCount(FetchDescriptor<SnippetGroup>(predicate: #Predicate { $0.keyword == sampleGroupKeyword })) == 0 {
      try applySnippetGroupEdit(
        snippetGroup: SnippetGroup(name: ""),
        name: "開発環境のセットアップ",
        keyword: ";dev-env",
        snippets: ["envkey", "envrc", "ghsec"].compactMap { snippetsByKeyword[$0] },
        modelContext: modelContext,
        now: now
      )
    }
    try modelContext.save()
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
          appDelegate.launcherPanelController?.insertSampleSnippets()
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
    /// デザイン (`documents/design/Main.dc.html`) の例と同じスニペットを入れる。同じキーワードのスニペットがあれば入れないため、何度押しても増えない。
    ///
    /// 本文は画面の確認で撮影して公開するため、偽の値だけにする (`.claude/rules/snippet-content-handling.md`)。
    func insertSampleSnippets() {
      let modelContext = modelContainer.mainContext
      do {
        let existingKeywords = Set(try modelContext.fetch(FetchDescriptor<Snippet>()).compactMap(\.keyword))
        let folder = Folder(name: "開発環境")
        let tags = [Tag(name: "shell"), Tag(name: "auth")]
        // 同じ種類の一致は更新日時の新しい順に並ぶため、デザインの並び (envkey が先) になるよう更新日時をずらす。
        let sampleSnippets: [(keyword: String, title: String, body: String, color: SnippetColor, updatedAt: Date)] = [
          (
            "envkey", "環境変数からトークンを取得",
            "# API_TOKEN が未設定ならダミー値で進める\nexport API_TOKEN=\"${API_TOKEN:-dummy-token}\"\n\ncurl -sS \\\n  -H \"Authorization: Bearer ${API_TOKEN}\" \\\n  https://api.example.com/v1/me",
            .shu, Date(timeIntervalSinceNow: 0)
          ),
          ("envrc", ".envrc の雛形", "export API_TOKEN=dummy-token", .matsuba, Date(timeIntervalSinceNow: -60)),
          ("ghsec", "GitHub Actions の secrets 参照", "- run: ./scripts/deploy.sh\n  with:\n    token: ${{ secrets.DEPLOY_TOKEN }}", .ai, Date(timeIntervalSinceNow: -120)),
        ]
        for sampleSnippet in sampleSnippets where !existingKeywords.contains(sampleSnippet.keyword) {
          let snippet = Snippet(body: sampleSnippet.body)
          snippet.title = sampleSnippet.title
          snippet.keyword = sampleSnippet.keyword
          snippet.colorRawValue = sampleSnippet.color.rawValue
          snippet.updatedAt = sampleSnippet.updatedAt
          modelContext.insert(snippet)
          if sampleSnippet.keyword == "envkey" {
            snippet.folder = folder
            snippet.tags = tags
          }
        }
        try modelContext.save()
      } catch {
        developerCommandsLogger.error("Failed to insert sample snippets: \(String(describing: error), privacy: .public)")
      }
    }

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
        if let snippetGroup = snippetGroups.first(where: { $0.keyword == ";dev-env" }) ?? snippetGroups.first {
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

  /// 見本のスニペットを作り、その削除の依頼を確認の画面に出す。内容はデザイン (`documents/design/AgentDelete.dc.html`) の見本に合わせ、本文は偽の値にする。許可されたら見本を消す。
  ///
  /// キーワード `envrc` は「Insert Sample Snippets」の見本も使うため、使われていない時だけ付ける (キーワードはスニペットの間で一意)。
  func showSampleDeletionRequest(controller: MCPServerController) async {
    let modelContext = controller.modelContainer.mainContext
    let snippet = Snippet(body: "export API_TOKEN=dummy-token-for-test\nexport DATABASE_URL=postgres://localhost:5432/app_dev\nexport LOG_LEVEL=debug\n\ndotenv_if_exists .env.local")
    snippet.title = String(localized: ".envrc template")
    snippet.colorRawValue = SnippetColor.matsuba.rawValue
    let folder = Folder(name: String(localized: "Dev environment"))
    do {
      let sampleKeyword: String? = "envrc"
      if try modelContext.fetchCount(FetchDescriptor<Snippet>(predicate: #Predicate { $0.keyword == sampleKeyword })) == 0 {
        snippet.keyword = sampleKeyword
      }
      modelContext.insert(snippet)
      modelContext.insert(folder)
      snippet.folder = folder
      snippet.tags = ["shell", "direnv"].map { tagName in
        let tag = Tag(name: tagName)
        modelContext.insert(tag)
        return tag
      }
      try modelContext.save()
    } catch {
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
