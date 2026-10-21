import Foundation
import SwiftData
import UniformTypeIdentifiers

/// スニペット・スニペットグループを保存する前の検査で見つかった問題。`description` は画面にそのまま表示する。
public enum SnippetValidationError: Error, Equatable, CustomStringConvertible {
  /// キーワードが別のスニペットかスニペットグループで使われている。
  case keywordAlreadyUsed(keyword: String)
  /// キーワードが空白と改行だけ。
  case blankKeyword
  /// キーワードが最小の文字数 (`snippetKeywordMinimumLength`) より短い。
  case keywordTooShort(minimumLength: Int)
  /// 本文が空 (空白と改行だけの本文を含む)。添付のスニペットでは出さない。
  case emptyBody
  /// 添付のデータが上限 (`snippetAttachmentMaximumByteCount`) より大きい。
  case attachmentTooLarge(maximumByteCount: Int)
  /// 添付の種類が画像でも動画でもない。
  case unsupportedAttachmentType(contentType: String)
  /// 添付のスニペットの本文を書き換えようとした。添付のスニペットは本文を持たない (`documents/DIRECTION.md`「決めたこと」)。
  case bodyOfAttachmentSnippet

  /// 画面にそのまま表示する文言。アプリと拡張のどこから表示しても同じ翻訳になるよう、このパッケージの翻訳を使う。
  public var description: String {
    switch self {
    case .keywordAlreadyUsed(let keyword):
      String(localized: "The keyword \"\(keyword)\" is already used by another snippet or snippet group.", bundle: .module)
    case .blankKeyword:
      String(localized: "The keyword cannot be only spaces.", bundle: .module)
    case .keywordTooShort(let minimumLength):
      String(localized: "The keyword must be at least \(minimumLength) characters.", bundle: .module)
    case .emptyBody:
      String(localized: "The snippet body is empty.", bundle: .module)
    case .attachmentTooLarge(let maximumByteCount):
      String(
        localized: "The image or video is too large. Choose one that is \(Int64(maximumByteCount).formatted(.byteCount(style: .file))) or smaller.",
        bundle: .module
      )
    case .unsupportedAttachmentType(let contentType):
      String(localized: "Only images and videos can be added. This file is \(contentType).", bundle: .module)
    case .bodyOfAttachmentSnippet:
      String(localized: "This snippet holds an image or video, so its body cannot be set.", bundle: .module)
    }
  }
}

/// 本文が空のスニペットを保存させないための検査。空白と改行だけの本文は出力しても何も入らないため空とみなす。
public func validateSnippetBody(body: String) throws {
  if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    throw SnippetValidationError.emptyBody
  }
}

/// スニペットの中身 (本文か添付のどちらか) の検査。添付が無ければ本文が空でないこと、添付があれば大きさと種類を確かめる。
///
/// 添付があるスニペットは本文を空で保存するため (`applySnippetEdit`)、本文は確かめない。
public func validateSnippetContent(body: String, attachmentData: Data?, attachmentContentType: String?) throws {
  guard let attachmentData, let attachmentContentType else {
    try validateSnippetBody(body: body)
    return
  }
  guard attachmentData.count <= snippetAttachmentMaximumByteCount else {
    throw SnippetValidationError.attachmentTooLarge(maximumByteCount: snippetAttachmentMaximumByteCount)
  }
  guard let contentType = UTType(attachmentContentType), snippetAttachmentAllowedContentTypes.contains(where: { contentType.conforms(to: $0) }) else {
    throw SnippetValidationError.unsupportedAttachmentType(contentType: attachmentContentType)
  }
}

/// キーワードの最小の文字数。キーワード展開は打った文字の末尾がキーワードと一致した時点で置き換えるため、1 文字のキーワードは普段の入力でその文字を打つたびに置き換わる。
public let snippetKeywordMinimumLength = 2

/// キーワードの書式の検査。空白と改行だけのキーワードと、`snippetKeywordMinimumLength` より短いキーワードを保存させない。
///
/// 空白だけのキーワードは文章の途中の空白で置き換わり、短いキーワードは普段の入力で置き換わるため。`nil` と空文字はキーワードなしとして検査しない。
public func validateKeywordFormat(keyword: String?) throws {
  guard let keyword, !keyword.isEmpty else {
    return
  }
  if keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    throw SnippetValidationError.blankKeyword
  }
  if keyword.count < snippetKeywordMinimumLength {
    throw SnippetValidationError.keywordTooShort(minimumLength: snippetKeywordMinimumLength)
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
