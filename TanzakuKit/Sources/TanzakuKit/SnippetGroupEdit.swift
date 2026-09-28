import Foundation
import SwiftData

/// ユーザーが編集画面で入力した値を、保存前の検査を通してからスニペットグループに書き込む。保存 (`modelContext.save()`) は呼び出し側で行う。
///
/// `snippetGroup` には既存のグループか、まだストアに入れていない新規のグループを渡し、新規のグループは検査を通った時だけストアに入れる (理由は `applySnippetEdit` と同じ)。
/// `snippets` はメニューに並べる順のスニペット。同じスニペットは最初の 1 つだけを残す。
/// 既に項目があるスニペットは項目を使い回して並び順だけを変える。同期するストアのレコードを作り直さず、変更を最小にするため。
public func applySnippetGroupEdit(
  snippetGroup: SnippetGroup,
  name: String,
  keyword: String,
  snippets: [Snippet],
  modelContext: ModelContext,
  now: Date
) throws {
  let optionalKeyword = keyword.isEmpty ? nil : keyword
  try validateKeywordIsUnique(keyword: optionalKeyword, ownerID: snippetGroup.id, modelContext: modelContext)
  if snippetGroup.modelContext == nil {
    snippetGroup.createdAt = now
    modelContext.insert(snippetGroup)
  }
  snippetGroup.name = name
  snippetGroup.keyword = optionalKeyword
  var unusedItemsBySnippetID = Dictionary(
    (snippetGroup.items ?? []).compactMap { item in item.snippet.map { ($0.id, item) } },
    uniquingKeysWith: { first, _ in first }
  )
  var placedSnippetIDs = Set<UUID>()
  var items: [SnippetGroupItem] = []
  for snippet in snippets where placedSnippetIDs.insert(snippet.id).inserted {
    let item = unusedItemsBySnippetID.removeValue(forKey: snippet.id) ?? {
      let item = SnippetGroupItem(sortIndex: 0)
      modelContext.insert(item)
      item.snippet = snippet
      return item
    }()
    item.sortIndex = items.count
    items.append(item)
  }
  let keptItemIDs = Set(items.map(\.id))
  for item in snippetGroup.items ?? [] where !keptItemIDs.contains(item.id) {
    modelContext.delete(item)
  }
  snippetGroup.items = items
  snippetGroup.updatedAt = now
}

/// スニペットグループの項目をメニューに並べる順で返す。SwiftData の配列リレーションは順序を保証しないため、`sortIndex` で並べる。
public func sortedSnippetGroupItems(snippetGroup: SnippetGroup) -> [SnippetGroupItem] {
  (snippetGroup.items ?? []).sorted { $0.sortIndex < $1.sortIndex }
}
