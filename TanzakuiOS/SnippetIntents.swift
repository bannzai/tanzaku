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
  /// ショートカットの選択肢に出す名前 (`snippetDisplayTitle(snippet:)`)。
  let displayTitle: String
  /// ショートカットの選択肢の 2 行目に出すキーワード。
  let keyword: String?

  /// ショートカットの選択肢の表示。
  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(displayTitle)", subtitle: keyword.map { "\($0)" })
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
/// ストアとクリップボードをメインスレッドで扱うため、ほかの App Intents の型と違い nonisolated にしない (`@Parameter` は nonisolated の型に置けない)。
struct CopySnippetIntent: AppIntent {
  /// ショートカットの画面に出す名前。
  static var title: LocalizedStringResource {
    "Copy Snippet"
  }

  /// ショートカットの画面に出す説明。
  static var description: IntentDescription {
    IntentDescription("Copies the body of the selected snippet to the clipboard.")
  }

  /// コピーするスニペット。ショートカットで決めていなければ実行時に選ばせる。
  @Parameter(title: "Snippet")
  var snippet: SnippetAppEntity

  /// 選んだスニペットの本文をコピーし、コピーしたスニペットの名前を伝える。
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let copiedSnippetTitle = try copySnippetBodyForIntent(snippetID: snippet.id)
    return .result(dialog: "Copied “\(copiedSnippetTitle)”")
  }
}

/// ショートカットのアプリに、設定なしで出す intent。`CopySnippetIntent` を作るため、それと同じくメインスレッドに置く。
struct TanzakuAppShortcuts: AppShortcutsProvider {
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
  snippets.map { SnippetAppEntity(id: $0.id, displayTitle: snippetDisplayTitle(snippet: $0), keyword: $0.keyword) }
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

/// 識別子のスニペットの本文をクリップボードへコピーし、そのスニペットの名前を返す。
private func copySnippetBodyForIntent(snippetID: UUID) throws -> String {
  snippetDisplayTitle(
    snippet: try copySnippetBody(
      snippetID: snippetID,
      modelContext: iosModelContainerResult.get().mainContext,
      pasteboardWriter: copySnippetBodyToPasteboard(body:)
    )
  )
}
