import Foundation
import SwiftData

/// 前後の空白と改行を除き、空になったら `nil` にする。任意の項目 (タイトル・キーワード) の空欄を「無し」として保存するため。
func nonEmptyTrimmedText(text: String?) -> String? {
  guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
    return nil
  }
  return trimmed
}

/// 編集画面で変えたスニペットを検査し、更新した主体と日時を入れて保存する。検査で見つかった問題は `SnippetValidationError` で投げ、保存しない。
///
/// タイトルとキーワードは前後の空白を除き、空なら無しにする。キーワード展開は打った文字列をそのまま照合するため、前後の空白を含むキーワードは打てないため。
/// `snippet` は `modelContext` に入れた後に呼ぶ。同じ `now` で何度呼んでも結果は同じ。
public func saveEditedSnippet(snippet: Snippet, modelContext: ModelContext, now: Date) throws {
  try validateSnippetBody(body: snippet.body)
  snippet.title = nonEmptyTrimmedText(text: snippet.title)
  snippet.keyword = nonEmptyTrimmedText(text: snippet.keyword)
  try validateKeywordIsUnique(keyword: snippet.keyword, ownerID: snippet.id, modelContext: modelContext)
  snippet.updatedAt = now
  snippet.updatedByKind = snippetAuthorUserKind
  snippet.updatedByClientName = nil
  try modelContext.save()
}

/// 名前が一致するタグを返し、無ければ作って `modelContext` に入れる。名前が空白だけなら `nil`。
///
/// 同じ名前のタグを 2 つ作らないため、編集画面でタグを足す時はこれを通す。保存は呼び出し側で行う。
public func findOrInsertTag(name: String, modelContext: ModelContext) throws -> Tag? {
  guard let trimmedName = nonEmptyTrimmedText(text: name) else {
    return nil
  }
  if let tag = try modelContext.fetch(FetchDescriptor<Tag>(predicate: #Predicate { $0.name == trimmedName })).first {
    return tag
  }
  let tag = Tag(name: trimmedName)
  modelContext.insert(tag)
  return tag
}

/// 名前が一致するフォルダを返し、無ければ作って `modelContext` に入れる。名前が空白だけなら `nil`。
///
/// 同じ名前のフォルダを 2 つ作らないため、編集画面でフォルダを作る時はこれを通す。保存は呼び出し側で行う。
public func findOrInsertFolder(name: String, modelContext: ModelContext) throws -> Folder? {
  guard let trimmedName = nonEmptyTrimmedText(text: name) else {
    return nil
  }
  if let folder = try modelContext.fetch(FetchDescriptor<Folder>(predicate: #Predicate { $0.name == trimmedName })).first {
    return folder
  }
  let folder = Folder(name: trimmedName)
  modelContext.insert(folder)
  return folder
}

/// スニペットを消して保存する。スニペットグループの項目はリレーションの削除ルールで消える。
///
/// 端末内のストアの意味検索のベクトルはストアをまたいでリレーションを張れないため、ここで一緒に消す。埋め込みモデルの資産が無い端末では `updateSnippetEmbeddings(modelContext:embedder:)` が呼ばれず、残り続けるため。
public func deleteSnippets(snippets: [Snippet], modelContext: ModelContext) throws {
  let snippetIDs = Set(snippets.map(\.id))
  for embedding in try modelContext.fetch(FetchDescriptor<SnippetEmbedding>()) where snippetIDs.contains(embedding.snippetID) {
    modelContext.delete(embedding)
  }
  for snippet in snippets {
    modelContext.delete(snippet)
  }
  try modelContext.save()
}
