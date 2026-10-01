import AppIntents
import Foundation
import SwiftData
import TanzakuKit

/// ショートカット・アクションボタンで選ぶスニペット。App Intents はモデルを直接受け渡せず、`AppEntity` を求めるため置く。
///
/// App Intents の実行はメインスレッドの外から呼ばれ、`Sendable` を求められるため nonisolated にする。ストアを読むのはメインスレッドの関数 (`snippetAppEntities(snippets:)` など) に任せる。
nonisolated struct SnippetAppEntity: AppEntity {
  /// ショートカットの画面に出す、このエンティティの種類の名前。
  static var typeDisplayRepresentation: TypeDisplayRepresentation {
    TypeDisplayRepresentation(name: "Snippet")
  }

  /// スニペットを探す問い合わせ。
  static var defaultQuery: SnippetAppEntityQuery {
    SnippetAppEntityQuery()
  }

  /// `Snippet.id`。
  let id: UUID
  /// `Snippet.title`。
  let title: String?
  /// `Snippet.keyword`。
  let keyword: String?

  /// ショートカットの選択肢の表示。名前はタイトル (無ければキーワード) にし、どちらも無ければ「Untitled Snippet」にする。
  ///
  /// 本文の 1 行目 (`snippetDisplayTitle(snippet:)`) は使わない。Siri が選択肢を読み上げることがあり、本文の秘匿情報を周りに聞かせてしまうため (`.claude/rules/snippet-content-handling.md`)。
  var displayRepresentation: DisplayRepresentation {
    switch (title, keyword) {
    case (.some(let title), .some(let keyword)):
      DisplayRepresentation(title: "\(title)", subtitle: "\(keyword)")
    case (.some(let title), .none):
      DisplayRepresentation(title: "\(title)")
    case (.none, .some(let keyword)):
      DisplayRepresentation(title: "\(keyword)")
    case (.none, .none):
      DisplayRepresentation(title: "Untitled Snippet")
    }
  }
}

/// ショートカットでスニペットを選ぶ時の問い合わせ。文字を入れると `snippetIntentSearchResults` で検索する。
nonisolated struct SnippetAppEntityQuery: EntityStringQuery {
  /// ショートカットに保存した識別子のスニペット。消されたものは返さない。
  func entities(for identifiers: [UUID]) async throws -> [SnippetAppEntity] {
    try await snippetAppEntities(snippetIDs: identifiers)
  }

  /// 入力した文字列で検索したスニペット。
  func entities(matching string: String) async throws -> [SnippetAppEntity] {
    try await searchedSnippetAppEntities(query: string)
  }

  /// 文字を入れる前に並べるスニペット。更新日時の新しい順 (本体の一覧と同じ)。
  func suggestedEntities() async throws -> [SnippetAppEntity] {
    try await recentSnippetAppEntities()
  }
}

/// スニペットを選んで本文をクリップボードへコピーする intent。ショートカット・アクションボタンから使う (`documents/PROJECT.md`「iOS > Spotlight・App Intents」)。
///
/// アプリを前面に出さずにコピーだけ済ませるため、アプリを開かない (`openAppWhenRun` の既定の `false`)。
/// `@Parameter` の可変のプロパティは nonisolated の型に置けないため、型は nonisolated にせず、App Intents が呼ぶ要素と準拠を nonisolated にする。
/// App Intents はメインスレッドの外でこの型を作り、名前を読み、`perform()` を呼ぶため。ストアとクリップボードはメインスレッドの関数に任せる。
struct CopySnippetIntent: nonisolated AppIntent {
  /// ショートカットの画面に出す名前。
  nonisolated static var title: LocalizedStringResource {
    "Copy Snippet"
  }

  /// ショートカットの画面に出す説明。
  nonisolated static var description: IntentDescription {
    IntentDescription("Copies the body of the selected snippet to the clipboard.")
  }

  /// コピーするスニペット。ショートカットで決めていなければ実行時に選ばせる。
  @Parameter(title: "Snippet")
  var snippet: SnippetAppEntity

  /// App Intents がメインスレッドの外から作るため nonisolated にする。値はショートカットが `snippet` に入れる。
  nonisolated init() {}

  /// 選んだスニペットの本文をコピーし、コピーしたことを伝える。
  ///
  /// 伝える名前はタイトルかキーワードだけにし、どちらも無ければ名前を出さない。完了の文言は Siri が読み上げることがあり、本文の 1 行目 (`snippetDisplayTitle(snippet:)`) を使うと本文の秘匿情報を周りに聞かせてしまうため (`.claude/rules/snippet-content-handling.md`)。
  nonisolated func perform() async throws -> some IntentResult & ProvidesDialog {
    if let copiedSnippetName = try await copySnippetBodyForIntent(snippetID: snippet.id) {
      return .result(dialog: "Copied “\(copiedSnippetName)”")
    }
    return .result(dialog: "Copied the snippet")
  }
}

/// ショートカットのアプリに、設定なしで出す intent。App Intents がメインスレッドの外から読むため nonisolated にする。
nonisolated struct TanzakuAppShortcuts: AppShortcutsProvider {
  /// スニペットをコピーする intent。
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: CopySnippetIntent(),
      phrases: ["Copy a snippet with \(.applicationName)"],
      shortTitle: "Copy Snippet",
      systemImageName: "doc.on.doc"
    )
  }
}

/// ストアのスニペットから `SnippetAppEntity` を作る。
private func snippetAppEntities(snippets: [Snippet]) -> [SnippetAppEntity] {
  snippets.map { SnippetAppEntity(id: $0.id, title: $0.title, keyword: $0.keyword) }
}

/// 識別子のスニペットの `SnippetAppEntity`。
private func snippetAppEntities(snippetIDs: [UUID]) throws -> [SnippetAppEntity] {
  snippetAppEntities(
    snippets: try iosModelContainerResult.get().mainContext.fetch(FetchDescriptor<Snippet>(predicate: #Predicate { snippetIDs.contains($0.id) }))
  )
}

/// 入力した文字列で検索したスニペットの `SnippetAppEntity`。
///
/// 意味検索は使わず、文字列の一致だけで探す。埋め込みモデルの用意に数秒かかり、ショートカットの選択肢の入力のたびに待たせるため (`documents/DIRECTION.md`「決めたこと」)。
private func searchedSnippetAppEntities(query: String) throws -> [SnippetAppEntity] {
  snippetAppEntities(snippets: try snippetIntentSearchResults(query: query, modelContext: iosModelContainerResult.get().mainContext, embedder: nil))
}

/// 更新日時の新しい順のすべてのスニペットの `SnippetAppEntity`。
private func recentSnippetAppEntities() throws -> [SnippetAppEntity] {
  snippetAppEntities(
    snippets: try iosModelContainerResult.get().mainContext.fetch(FetchDescriptor<Snippet>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
  )
}

/// 識別子のスニペットの本文をクリップボードへコピーし、そのスニペットのタイトル (無ければキーワード) を返す。どちらも無ければ `nil`。本文から作った名前は返さない (`CopySnippetIntent.perform()`)。
private func copySnippetBodyForIntent(snippetID: UUID) throws -> String? {
  let snippet = try copySnippetBody(
    snippetID: snippetID,
    modelContext: iosModelContainerResult.get().mainContext,
    usedAt: .now,
    pasteboardWriter: copySnippetBodyToPasteboard(body:)
  )
  return snippet.title ?? snippet.keyword
}
