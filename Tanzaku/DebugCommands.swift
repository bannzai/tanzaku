#if DEBUG
  import SwiftData
  import SwiftUI
  import TanzakuKit

  /// Debug ビルドだけのメニュー。画面の確認で要る状態 (スニペットが並んだ管理ウィンドウ) を、simtunnel の runner 上でもメニューの操作だけで作るため
  /// (`AGENTS.md`「画面の確認」、起動引数より開発者メニューを優先する規約)。
  struct DebugCommands: Commands {
    /// 見本データを入れるストア。
    let modelContainer: ModelContainer

    var body: some Commands {
      CommandMenu("Debug") {
        Button("Insert Sample Data") {
          try? insertDebugSampleData(modelContext: modelContainer.mainContext, now: .now)
        }
        .keyboardShortcut("d", modifiers: [.command, .option, .shift])
      }
    }
  }

  /// デザイン (`documents/design/Manager.dc.html`) と同じ並びのスニペット・フォルダ・タグ・スニペットグループを入れる。
  ///
  /// 本文は明らかに偽の値にする (`.claude/rules/snippet-content-handling.md`)。見本のキーワード `envkey` のスニペットが既にあれば何もしないため、何度呼んでも同じ結果になる。
  func insertDebugSampleData(modelContext: ModelContext, now: Date) throws {
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
    try applySnippetGroupEdit(
      snippetGroup: SnippetGroup(name: ""),
      name: "開発環境のセットアップ",
      keyword: ";dev-env",
      snippets: ["envkey", "envrc", "ghsec"].compactMap { snippetsByKeyword[$0] },
      modelContext: modelContext,
      now: now
    )
    try modelContext.save()
  }
#endif
