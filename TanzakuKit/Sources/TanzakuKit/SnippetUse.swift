import Foundation
import SwiftData

/// ランチャーの検索語が空の時に出す、最近使ったスニペットの最大の件数。
///
/// issue #41 の仕様の値 (`documents/DIRECTION.md`「決めたこと」)。よく使うスニペットを打たずに選ぶための欄で、件数を増やすと選ぶまでの ↑↓ が増え、すべてのスニペットの一覧と変わらなくなるため。
public let recentlyUsedSnippetLimit = 10

/// スニペットを使った (コピー・貼り付け・挿入した) 日時を記録して保存する。同じ `usedAt` で何度呼んでも結果は同じになる。
///
/// `updatedAt` と更新の主体は変えない。使っただけで一覧の並び (更新日時の新しい順) が変わったり、編集したように見えたりしないため。
public func recordSnippetUse(snippet: Snippet, usedAt: Date, modelContext: ModelContext) throws {
  snippet.lastUsedAt = usedAt
  try modelContext.save()
}

/// 使ったことのあるスニペットを、使った日時の新しい順に最大 `recentlyUsedSnippetLimit` 件返す。
public func recentlyUsedSnippets(modelContext: ModelContext) throws -> [Snippet] {
  var fetchDescriptor = FetchDescriptor<Snippet>(
    predicate: #Predicate { $0.lastUsedAt != nil },
    sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)]
  )
  fetchDescriptor.fetchLimit = recentlyUsedSnippetLimit
  return try modelContext.fetch(fetchDescriptor)
}
