#if DEBUG
  import SwiftData
  import SwiftUI
  import TanzakuKit

  /// 開発者メニューで選ぶ外観の `UserDefaults` のキー。
  let developerAppearanceUserDefaultsKey = "developerAppearance"

  /// 開発者メニューで選ぶ外観。simtunnel の Simulator では外観の設定を外から変えられないため、アプリの中で切り替える。
  enum DeveloperAppearance: String {
    /// 端末の設定に従う。
    case system
    /// ライト。
    case light
    /// ダーク。
    case dark

    /// 画面に効かせる外観。`nil` は端末の設定に従う。
    var colorScheme: ColorScheme? {
      switch self {
      case .system:
        nil
      case .light:
        .light
      case .dark:
        .dark
      }
    }
  }

  /// Debug ビルドだけに出す開発者メニュー。simtunnel の画面の確認で、スニペットがある状態・無い状態とライト・ダークを作るため (`AGENTS.md`「画面の確認」)。
  ///
  /// 開発者向けの操作で翻訳しないため、文言は `Text(verbatim:)` にする。
  struct DeveloperMenu: View {
    /// スニペットを入れる・消すのに使う。
    @Environment(\.modelContext) private var modelContext
    /// 選んでいる外観。
    @AppStorage(developerAppearanceUserDefaultsKey) private var developerAppearance = DeveloperAppearance.system

    var body: some View {
      Menu {
        Button {
          insertSampleSnippets(modelContext: modelContext)
        } label: {
          Text(verbatim: "Insert Sample Snippets")
        }
        Button(role: .destructive) {
          deleteAllSnippets(modelContext: modelContext)
        } label: {
          Text(verbatim: "Delete All Snippets")
        }
        Picker(selection: $developerAppearance) {
          Text(verbatim: "System").tag(DeveloperAppearance.system)
          Text(verbatim: "Light").tag(DeveloperAppearance.light)
          Text(verbatim: "Dark").tag(DeveloperAppearance.dark)
        } label: {
          Text(verbatim: "Appearance")
        }
      } label: {
        Label {
          Text(verbatim: "Developer")
        } icon: {
          Image(systemName: "hammer")
        }
      }
      .accessibilityIdentifier("developerMenu")
    }
  }

  /// デザイン (`documents/design/Manager.dc.html`) の例と同じスニペット・フォルダ・タグ・スニペットグループを入れる。同じキーワードのスニペットがあれば入れないため、何度押しても増えない。
  ///
  /// 本文は画面の確認で撮影して公開するため、偽の値だけにする (`.claude/rules/snippet-content-handling.md`)。
  private func insertSampleSnippets(modelContext: ModelContext) {
    do {
      let existingKeywords = Set(try modelContext.fetch(FetchDescriptor<Snippet>()).compactMap(\.keyword))
      // 一覧は更新日時の新しい順に並ぶため、デザインの並びになるよう更新日時をずらす。
      let sampleSnippets: [(keyword: String, title: String, body: String, color: SnippetColor, language: SnippetLanguage?, folderName: String, tagNames: [String], minutesAgo: Double)] = [
        (
          "envkey", "環境変数からトークンを取得",
          "# API_TOKEN が未設定ならダミー値で進める\nexport API_TOKEN=\"${API_TOKEN:-dummy-token}\"\n\ncurl -sS \\\n  -H \"Authorization: Bearer ${API_TOKEN}\" \\\n  https://api.example.com/v1/me",
          .shu, .shell, "開発環境", ["shell"], 0
        ),
        ("envrc", ".envrc の雛形", "export API_TOKEN=dummy-token", .matsuba, .shell, "開発環境", ["shell"], 60),
        (
          "ghsec", "GitHub Actions の secrets 参照",
          "jobs:\n  deploy:\n    runs-on: ubuntu-latest\n    env:\n      API_TOKEN: ${{ secrets.API_TOKEN }}\n    steps:\n      - uses: actions/checkout@v4\n      - run: ./scripts/deploy.sh",
          .ai, .yaml, "GitHub", ["github-actions"], 120
        ),
        ("prrev", "PR レビュー依頼の文面", "レビューをお願いします。変更の目的は次のとおりです。", .yamabuki, nil, "文面", ["review"], 180),
        ("research", "Claude に渡す調査の指示", "次の件を調査して、結論から報告してください。", .murasaki, .markdown, "AI プロンプト", ["claude"], 240),
      ]
      var insertedSnippets: [Snippet] = []
      for sampleSnippet in sampleSnippets where !existingKeywords.contains(sampleSnippet.keyword) {
        let snippet = Snippet(body: sampleSnippet.body)
        modelContext.insert(snippet)
        snippet.title = sampleSnippet.title
        snippet.keyword = sampleSnippet.keyword
        snippet.colorRawValue = sampleSnippet.color.rawValue
        snippet.language = sampleSnippet.language?.rawValue
        snippet.updatedAt = Date(timeIntervalSinceNow: -sampleSnippet.minutesAgo * 60)
        snippet.folder = try findOrInsertFolder(name: sampleSnippet.folderName, modelContext: modelContext)
        snippet.tags = try sampleSnippet.tagNames.compactMap { try findOrInsertTag(name: $0, modelContext: modelContext) }
        if sampleSnippet.keyword == "research" {
          snippet.createdByKind = snippetAuthorMCPKind
          snippet.createdByClientName = "Claude Code"
          snippet.updatedByKind = snippetAuthorMCPKind
          snippet.updatedByClientName = "Claude Code"
        }
        insertedSnippets.append(snippet)
      }
      if !insertedSnippets.isEmpty {
        let snippetGroup = SnippetGroup(name: "開発の定型")
        snippetGroup.keyword = ";dev"
        modelContext.insert(snippetGroup)
        replaceSnippetGroupItems(snippetGroup: snippetGroup, snippets: insertedSnippets.filter { ["envkey", "envrc", "ghsec"].contains($0.keyword) }, modelContext: modelContext)
      }
      try modelContext.save()
    } catch {
      modelContext.rollback()
      assertionFailure("Failed to insert sample snippets: \(error)")
    }
  }

  /// スニペット・フォルダ・タグ・スニペットグループ・意味検索のベクトルをすべて消す。スニペットが無い画面を出すため。
  private func deleteAllSnippets(modelContext: ModelContext) {
    do {
      try modelContext.delete(model: Snippet.self)
      try modelContext.delete(model: Folder.self)
      try modelContext.delete(model: Tag.self)
      try modelContext.delete(model: SnippetGroup.self)
      try modelContext.delete(model: SnippetGroupItem.self)
      try modelContext.delete(model: SnippetEmbedding.self)
      try modelContext.save()
    } catch {
      modelContext.rollback()
      assertionFailure("Failed to delete snippets: \(error)")
    }
  }
#endif
