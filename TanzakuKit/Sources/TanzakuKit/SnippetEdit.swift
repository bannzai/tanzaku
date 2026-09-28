import Foundation
import SwiftData

/// ユーザーが編集画面で入力した値を、保存前の検査を通してからスニペットに書き込む。保存 (`modelContext.save()`) は呼び出し側で行う。
///
/// `snippet` には既存のスニペットか、まだストアに入れていない新規のスニペットを渡す。新規のスニペットは検査を通った時だけストアに入れる。
/// SwiftData は自動で保存するため、検査の前にストアに入れると空の本文や重複したキーワードのスニペットが保存されてしまうため。
/// 空のタイトル・キーワードは「なし」として `nil` にする。タグは名前で渡し、同じ名前のタグがあればそれを使い、無ければ作る。
/// 入力中のタグを都度ストアに入れると、保存しなかったタグが残るため、検査を通った後に作る。
public func applySnippetEdit(
  snippet: Snippet,
  body: String,
  title: String,
  keyword: String,
  language: SnippetLanguage?,
  color: SnippetColor?,
  folder: Folder?,
  tagNames: [String],
  modelContext: ModelContext,
  now: Date
) throws {
  try validateSnippetBody(body: body)
  let optionalKeyword = keyword.isEmpty ? nil : keyword
  try validateKeywordIsUnique(keyword: optionalKeyword, ownerID: snippet.id, modelContext: modelContext)
  snippet.body = body
  snippet.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : title
  snippet.keyword = optionalKeyword
  snippet.language = language?.rawValue
  snippet.colorRawValue = color?.rawValue
  snippet.updatedAt = now
  snippet.updatedByKind = "user"
  snippet.updatedByClientName = nil
  // 画面の `@Query` が中身の入ったスニペットとして受け取れるよう、属性を入れてからストアに入れる。リレーションは両方がストアに入っている必要があるため、その後に張る。
  if snippet.modelContext == nil {
    snippet.createdAt = now
    modelContext.insert(snippet)
  }
  snippet.folder = folder
  snippet.tags = try resolvedTags(tagNames: tagNames, modelContext: modelContext)
}

/// タグの名前から、同じ名前の既存のタグか、新しく作ったタグを返す。前後の空白を除き、空の名前と重複した名前は除く。
///
/// 名前の比較は大文字と小文字を区別した完全一致にする。キーワードの一意と同じ基準にそろえ、ユーザーが打った表記をそのまま残すため。
func resolvedTags(tagNames: [String], modelContext: ModelContext) throws -> [Tag] {
  let existingTagsByName = Dictionary(
    try modelContext.fetch(FetchDescriptor<Tag>()).map { ($0.name, $0) },
    uniquingKeysWith: { first, _ in first }
  )
  var resolvedTagNames = Set<String>()
  return tagNames
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty && resolvedTagNames.insert($0).inserted }
    .map { tagName in
      if let existingTag = existingTagsByName[tagName] {
        return existingTag
      }
      let tag = Tag(name: tagName)
      modelContext.insert(tag)
      return tag
    }
}
