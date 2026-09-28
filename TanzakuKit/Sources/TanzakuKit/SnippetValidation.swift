import Foundation
import SwiftData

/// スニペット・スニペットグループを保存する前の検査で見つかった問題。`description` は画面にそのまま表示する。
public enum SnippetValidationError: Error, Equatable, CustomStringConvertible {
  /// キーワードが別のスニペットかスニペットグループで使われている。
  case keywordAlreadyUsed(keyword: String)
  /// 本文が空 (空白と改行だけの本文を含む)。
  case emptyBody

  /// 画面にそのまま表示する文言。
  public var description: String {
    switch self {
    case .keywordAlreadyUsed(let keyword):
      "The keyword \"\(keyword)\" is already used by another snippet or snippet group."
    case .emptyBody:
      "The snippet body is empty."
    }
  }
}

/// 本文が空のスニペットを保存させないための検査。空白と改行だけの本文は出力しても何も入らないため空とみなす。
public func validateSnippetBody(body: String) throws {
  if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    throw SnippetValidationError.emptyBody
  }
}

/// キーワードがスニペットとスニペットグループで共通の名前空間で一意かの検査。
///
/// CloudKit と両立させるため `@Attribute(.unique)` を使えず (`documents/data-model.md`「CloudKit と両立させるための制約」)、一意はこの検査で保証する。
/// `ownerID` には保存しようとしているスニペットかスニペットグループの `id` を渡し、自分自身との一致は重複に数えない。
/// キーワード展開は打った文字列をそのまま照合するため、大文字と小文字は区別する。`nil` と空文字はキーワードなしとして検査しない。
public func validateKeywordIsUnique(keyword: String?, ownerID: UUID, modelContext: ModelContext) throws {
  guard let keyword, !keyword.isEmpty else {
    return
  }
  // #Predicate は Optional の属性と非 Optional の値を比べられないため、比べる値を Optional にそろえる。
  let optionalKeyword: String? = keyword
  if try modelContext.fetchCount(
    FetchDescriptor<Snippet>(predicate: #Predicate { $0.keyword == optionalKeyword && $0.id != ownerID })
  ) > 0 {
    throw SnippetValidationError.keywordAlreadyUsed(keyword: keyword)
  }
  if try modelContext.fetchCount(
    FetchDescriptor<SnippetGroup>(predicate: #Predicate { $0.keyword == optionalKeyword && $0.id != ownerID })
  ) > 0 {
    throw SnippetValidationError.keywordAlreadyUsed(keyword: keyword)
  }
}
