import Foundation
import SwiftData

/// スニペットグループのメニューに並ぶスニペットを、メニューに出す順 (`SnippetGroupItem.sortIndex`) で返す。スニペットが消えた項目は飛ばす。
public func snippetGroupSnippets(snippetGroup: SnippetGroup) -> [Snippet] {
  (snippetGroup.items ?? [])
    .sorted { $0.sortIndex < $1.sortIndex }
    .compactMap(\.snippet)
}

/// スニペットグループのメニューの項目を `snippets` の並びに置き換える。保存は呼び出し側で行う。
///
/// 残るスニペットの項目は作り直さず並び順だけを変え、外したスニペットの項目は消す。同じスニペットが 2 回あれば最初の位置だけを使う。同じ `snippets` で何度呼んでも結果は同じ。
public func replaceSnippetGroupItems(snippetGroup: SnippetGroup, snippets: [Snippet], modelContext: ModelContext) {
  var keptSnippetIDs = Set<UUID>()
  let orderedSnippets = snippets.filter { keptSnippetIDs.insert($0.id).inserted }
  var itemsBySnippetID: [UUID: SnippetGroupItem] = [:]
  for item in snippetGroup.items ?? [] {
    if let snippetID = item.snippet?.id, keptSnippetIDs.contains(snippetID), itemsBySnippetID[snippetID] == nil {
      itemsBySnippetID[snippetID] = item
    } else {
      modelContext.delete(item)
    }
  }
  for (index, snippet) in orderedSnippets.enumerated() {
    if let item = itemsBySnippetID[snippet.id] {
      item.sortIndex = index
    } else {
      let item = SnippetGroupItem(sortIndex: index)
      modelContext.insert(item)
      item.group = snippetGroup
      item.snippet = snippet
    }
  }
}

/// 編集画面で変えたスニペットグループを検査し、更新日時を入れて保存する。検査で見つかった問題は `SnippetValidationError` で投げ、保存しない。
///
/// 名前は管理画面・サイドバーに出すため必須にする。キーワードはスニペットと同じく前後の空白を除き、空なら無しにする (`saveEditedSnippet(snippet:modelContext:now:)`)。
/// `snippetGroup` は `modelContext` に入れた後に呼ぶ。同じ `now` で何度呼んでも結果は同じ。
public func saveEditedSnippetGroup(snippetGroup: SnippetGroup, modelContext: ModelContext, now: Date) throws {
  guard let name = nonEmptyTrimmedText(text: snippetGroup.name) else {
    throw SnippetValidationError.emptySnippetGroupName
  }
  snippetGroup.name = name
  snippetGroup.keyword = nonEmptyTrimmedText(text: snippetGroup.keyword)
  try validateKeywordIsUnique(keyword: snippetGroup.keyword, ownerID: snippetGroup.id, modelContext: modelContext)
  snippetGroup.updatedAt = now
  try modelContext.save()
}
