#if DEBUG
  import CoreSpotlight
  import SwiftData
  import SwiftUI
  import TanzakuKit
  import os

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
    /// 入れた・消したスニペットの意味検索のベクトルを作り直させる。
    @Environment(SnippetEmbeddingController.self) private var snippetEmbeddingController
    /// 選んでいる外観。
    @AppStorage(developerAppearanceUserDefaultsKey) private var developerAppearance = DeveloperAppearance.system
    /// Spotlight の索引を調べた結果。表示している間だけ値を持つ。
    @State private var spotlightIndexReport: String?

    var body: some View {
      Menu {
        Button {
          Task {
            spotlightIndexReport = await snippetSpotlightIndexReport()
          }
        } label: {
          Text(verbatim: "Check Spotlight Index")
        }
        Button {
          insertSampleSnippets(modelContext: modelContext)
          Task {
            await snippetEmbeddingController.refreshEmbeddings()
          }
        } label: {
          Text(verbatim: "Insert Sample Snippets")
        }
        Button(role: .destructive) {
          deleteAllSnippets(modelContext: modelContext)
          Task {
            await snippetEmbeddingController.refreshEmbeddings()
          }
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
      .alert(
        Text(verbatim: "Spotlight Index"),
        isPresented: Binding(get: { spotlightIndexReport != nil }, set: { _ in spotlightIndexReport = nil })
      ) {
        Button {
        } label: {
          Text(verbatim: "OK")
        }
      } message: {
        Text(verbatim: spotlightIndexReport ?? "")
      }
    }
  }

  /// このアプリが Spotlight の索引に入れた項目を読み、件数と項目ごとのタイトル・キーワード・説明・本文の属性 (`textContent`) の有無を並べた文言を返す。
  ///
  /// simtunnel の Simulator の Spotlight の画面はこのアプリ自体も検索結果に出さず、画面では索引の中身を確かめられなかったため、アプリの中から索引を読む。
  private func snippetSpotlightIndexReport() async -> String {
    switch await snippetSpotlightIndexedItemDescriptions() {
    case .success(let itemDescriptions):
      (["\(itemDescriptions.count) items"] + itemDescriptions).joined(separator: "\n")
    case .failure(let error):
      "Failed: \(error)"
    }
  }

  /// `CSSearchQuery` でこのアプリが索引に入れた項目 (どれもタイトルを持つ) をすべて読み、項目ごとの説明の文字列を返す。
  ///
  /// `CSSearchQuery` の結果の通知はメインスレッドの外で呼ばれるため、メインスレッドに縛らないよう nonisolated にする。
  private nonisolated func snippetSpotlightIndexedItemDescriptions() async -> Result<[String], any Error> {
    let queryContext = CSSearchQueryContext()
    queryContext.fetchAttributes = ["title", "keywords", "contentDescription", "textContent"]
    let query = CSSearchQuery(queryString: "title == \"*\"", queryContext: queryContext)
    let itemDescriptions = OSAllocatedUnfairLock(initialState: [String]())
    let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<[String], any Error>, Never>) in
      query.foundItemsHandler = { searchableItems in
        // `CSSearchableItem` は Sendable でなく、ロックの閉包へ持ち込めないため、先に文字列にする。
        let foundItemDescriptions = searchableItems.map { searchableItem in
          let attributeSet = searchableItem.attributeSet
          return
            "title=\(attributeSet.title ?? "nil") keywords=\(attributeSet.keywords ?? []) description=\(attributeSet.contentDescription ?? "nil") textContent=\(attributeSet.textContent == nil ? "nil" : "set")"
        }
        itemDescriptions.withLock { $0 += foundItemDescriptions }
      }
      query.completionHandler = { error in
        continuation.resume(returning: error.map { .failure($0) } ?? .success(itemDescriptions.withLock { $0 }))
      }
      query.start()
    }
    // 結果が届くまで問い合わせを解放しないため。
    withExtendedLifetime(query) {}
    return result
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
        let snippet = Snippet(body: "")
        try applySnippetEdit(
          snippet: snippet,
          body: sampleSnippet.body,
          title: sampleSnippet.title,
          keyword: sampleSnippet.keyword,
          language: sampleSnippet.language,
          color: sampleSnippet.color,
          folder: try sampleFolder(name: sampleSnippet.folderName, modelContext: modelContext),
          tagNames: sampleSnippet.tagNames,
          modelContext: modelContext,
          now: Date(timeIntervalSinceNow: -sampleSnippet.minutesAgo * 60)
        )
        if sampleSnippet.keyword == "research" {
          snippet.createdByKind = "mcp"
          snippet.createdByClientName = "Claude Code"
          snippet.updatedByKind = "mcp"
          snippet.updatedByClientName = "Claude Code"
        }
        insertedSnippets.append(snippet)
      }
      if !insertedSnippets.isEmpty {
        try applySnippetGroupEdit(
          snippetGroup: SnippetGroup(name: ""),
          name: "開発の定型",
          keyword: ";dev",
          snippets: insertedSnippets.filter { ["envkey", "envrc", "ghsec"].contains($0.keyword) },
          modelContext: modelContext,
          now: .now
        )
      }
      try modelContext.save()
    } catch {
      modelContext.rollback()
      developerMenuLogger.error("Failed to insert sample snippets: \(String(describing: error), privacy: .public)")
    }
  }

  /// 名前が一致するフォルダを返し、無ければ作る。見本の 2 つのスニペットが同じフォルダに入るよう、作ったフォルダも次の見本で使う。
  private func sampleFolder(name: String, modelContext: ModelContext) throws -> Folder {
    if let folder = try modelContext.fetch(FetchDescriptor<Folder>(predicate: #Predicate { $0.name == name })).first {
      return folder
    }
    let folder = Folder(name: name)
    modelContext.insert(folder)
    return folder
  }

  /// スニペット・フォルダ・タグ・スニペットグループ・意味検索のベクトルをすべて消す。スニペットが無い画面を出すため。
  ///
  /// Mac の開発者メニュー (`deleteAllSnippetData(modelContext:)`) と同じく 1 件ずつ消す。失敗しても落とさず記録だけにする。
  private func deleteAllSnippets(modelContext: ModelContext) {
    do {
      for snippet in try modelContext.fetch(FetchDescriptor<Snippet>()) {
        modelContext.delete(snippet)
      }
      for folder in try modelContext.fetch(FetchDescriptor<Folder>()) {
        modelContext.delete(folder)
      }
      for tag in try modelContext.fetch(FetchDescriptor<Tag>()) {
        modelContext.delete(tag)
      }
      for snippetGroup in try modelContext.fetch(FetchDescriptor<SnippetGroup>()) {
        modelContext.delete(snippetGroup)
      }
      for snippetEmbedding in try modelContext.fetch(FetchDescriptor<SnippetEmbedding>()) {
        modelContext.delete(snippetEmbedding)
      }
      try modelContext.save()
    } catch {
      modelContext.rollback()
      developerMenuLogger.error("Failed to delete snippets: \(String(describing: error), privacy: .public)")
    }
  }

  /// 開発者メニューの失敗の記録。スニペットの本文は入れない (`.claude/rules/snippet-content-handling.md`)。
  private let developerMenuLogger = Logger(subsystem: "com.bannzai.tanzaku", category: "DeveloperMenu")
#endif
