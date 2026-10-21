import AppIntents
import Foundation
import SwiftData
import TanzakuKit
import UIKit

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
///
/// `EntityQuery` には `CopySnippetIntent.authenticationPolicy` に当たる設定が無いため、端末がロック中の時はスニペットを返さず `SnippetIntentDeviceLockedError` を投げる (`requireUnlockedDeviceForSnippetIntent(isProtectedDataAvailable:)`)。Siri が候補としてタイトル・キーワードを読み上げるため。
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

  /// 実行に端末のロック解除を求める。既定の `.alwaysAllowed` のままだと、ロック中の端末から Siri 経由で本文をコピーでき、完了の文言でタイトルも読み上げられるため (`.claude/rules/snippet-content-handling.md`)。
  nonisolated static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

  /// コピーするスニペット。ショートカットで決めていなければ実行時に選ばせる。
  @Parameter(title: "Snippet")
  var snippet: SnippetAppEntity

  /// App Intents がメインスレッドの外から作るため nonisolated にする。値はショートカットが `snippet` に入れる。
  nonisolated init() {}

  /// 選んだスニペットの本文をコピーし、コピーしたことを伝える。
  ///
  /// 伝える名前はタイトルかキーワードだけにし、どちらも無ければ名前を出さない。完了の文言は Siri が読み上げることがあり、本文の 1 行目 (`snippetDisplayTitle(snippet:)`) を使うと本文の秘匿情報を周りに聞かせてしまうため (`.claude/rules/snippet-content-handling.md`)。
  nonisolated func perform() async throws -> some IntentResult & ProvidesDialog {
    if let copiedSnippetName = try await copySnippetForIntent(snippetID: snippet.id) {
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

/// 端末がロック中のため、ショートカット・Siri にスニペットを返せないことを表すエラー。
///
/// App Intents は `CustomLocalizedStringResourceConvertible` の文言を Siri・ショートカットに出す。文言にスニペットの中身を入れない。
nonisolated struct SnippetIntentDeviceLockedError: Error, CustomStringConvertible, CustomLocalizedStringResourceConvertible {
  /// Siri・ショートカットに出す文言。
  var localizedStringResource: LocalizedStringResource {
    "Unlock your device to use snippets"
  }

  /// ログ・テストで読む文言。`localizedStringResource` と同じ。
  var description: String {
    String(localized: localizedStringResource)
  }
}

/// 端末がロック中なら `SnippetIntentDeviceLockedError` を投げる。`SnippetAppEntityQuery` がスニペットを返す前に通す。
///
/// `isProtectedDataAvailable` は `UIApplication.isProtectedDataAvailable` を渡す。パスコードを設定した端末のロック中だけ `false` になる。
func requireUnlockedDeviceForSnippetIntent(isProtectedDataAvailable: Bool) throws {
  guard isProtectedDataAvailable else {
    throw SnippetIntentDeviceLockedError()
  }
}

/// ストアのスニペットから `SnippetAppEntity` を作る。
private func snippetAppEntities(snippets: [Snippet]) -> [SnippetAppEntity] {
  snippets.map { SnippetAppEntity(id: $0.id, title: $0.title, keyword: $0.keyword) }
}

/// 識別子のスニペットの `SnippetAppEntity`。
private func snippetAppEntities(snippetIDs: [UUID]) throws -> [SnippetAppEntity] {
  try requireUnlockedDeviceForSnippetIntent(isProtectedDataAvailable: UIApplication.shared.isProtectedDataAvailable)
  return snippetAppEntities(
    snippets: try iosModelContainerResult.get().mainContext.fetch(FetchDescriptor<Snippet>(predicate: #Predicate { snippetIDs.contains($0.id) }))
  )
}

/// 入力した文字列で検索したスニペットの `SnippetAppEntity`。
///
/// 意味検索は使わず、文字列の一致だけで探す。埋め込みモデルの用意に数秒かかり、ショートカットの選択肢の入力のたびに待たせるため (`documents/DIRECTION.md`「決めたこと」)。
private func searchedSnippetAppEntities(query: String) throws -> [SnippetAppEntity] {
  try requireUnlockedDeviceForSnippetIntent(isProtectedDataAvailable: UIApplication.shared.isProtectedDataAvailable)
  return snippetAppEntities(snippets: try snippetIntentSearchResults(query: query, modelContext: iosModelContainerResult.get().mainContext, embedder: nil))
}

/// 更新日時の新しい順のすべてのスニペットの `SnippetAppEntity`。
private func recentSnippetAppEntities() throws -> [SnippetAppEntity] {
  try requireUnlockedDeviceForSnippetIntent(isProtectedDataAvailable: UIApplication.shared.isProtectedDataAvailable)
  return snippetAppEntities(
    snippets: try iosModelContainerResult.get().mainContext.fetch(FetchDescriptor<Snippet>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
  )
}

/// 識別子のスニペットの中身 (本文か添付) をクリップボードへコピーし、そのスニペットのタイトル (無ければキーワード) を返す。どちらも無ければ `nil`。本文から作った名前は返さない (`CopySnippetIntent.perform()`)。
private func copySnippetForIntent(snippetID: UUID) throws -> String? {
  let snippet = try copySnippet(
    snippetID: snippetID,
    modelContext: iosModelContainerResult.get().mainContext,
    usedAt: .now,
    pasteboardWriter: copySnippetToPasteboard(snippet:)
  )
  return snippet.title ?? snippet.keyword
}
