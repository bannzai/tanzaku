import Foundation
import SwiftData

/// 自動で付けるタイトルの最大の文字数。
///
/// 管理ウィンドウの一覧の最小の幅 (280pt) の 1 行に、見出しの文字 (13pt) でおよそ収まる長さ。言語モデルが指示より長い文を返した時に、一覧で切れるタイトルを付けないため。
public let generatedSnippetTitleMaxLength = 40

/// 自動で付けるタグの最大の数。
///
/// issue #55 の「タグも自動でつけられるようにする」に数の指定は無い。サイドバーのタグの一覧が 1 つのスニペットのタグで埋まらない数にする。
public let generatedSnippetTagLimit = 3

/// 自動で付けるタグ 1 つの最大の文字数。これより長い名前はタグにしない。
///
/// サイドバーの最小の幅 (200pt) の 1 行に収まる長さ。言語モデルがタグの代わりに文を返した時に、文をタグにしないため。
public let generatedSnippetTagNameMaxLength = 20

/// 言語モデルに「既にあるタグ」として渡すタグの最大の数。
///
/// 端末内の言語モデルが 1 回のやり取りで扱えるのは 4096 トークン ( https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window )。
/// タグをすべて渡すと、タグの多いライブラリではこの上限を超えてタグを作れなくなるため、数を決める。名前は `generatedSnippetTagNameMaxLength` 文字までのものに限るため、渡す文字数は区切りを含めて 660 文字までになる。
public let generatedSnippetTagPromptExistingTagLimit = 30

/// 言語モデルに「既にあるタグ」として渡すタグの名前。付けたスニペットが多い順 (同じ数なら名前の順) に `generatedSnippetTagPromptExistingTagLimit` 個まで。
///
/// よく使うタグほど新しいスニペットにも合いやすいため、多い順に選ぶ。`generatedSnippetTagNameMaxLength` 文字より長い名前は、言語モデルが返しても付けない (`generatedSnippetTagNames(generatedText:)`) ため渡さない。
public func generatedSnippetTagPromptExistingTagNames(tags: [Tag]) -> [String] {
  Array(
    tags
      .filter { $0.name.count <= generatedSnippetTagNameMaxLength }
      .sorted { firstTag, secondTag in
        let firstSnippetCount = (firstTag.snippets ?? []).count
        let secondSnippetCount = (secondTag.snippets ?? []).count
        return firstSnippetCount == secondSnippetCount ? firstTag.name < secondTag.name : firstSnippetCount > secondSnippetCount
      }
      .map(\.name)
      .prefix(generatedSnippetTagPromptExistingTagLimit)
  )
}

/// 言語モデルが返した文字列から、スニペットのタイトルにする文字列を取り出す。タイトルにできるものが無ければ `nil`。
///
/// 返すタイトルは 1 行で、囲みの引用符・かぎ括弧と前後の空白を含まず、`generatedSnippetTitleMaxLength` 文字以内。言語モデルは指示しても、複数行の応答・引用符で囲んだ応答・長い文を返すことがあるため。
public func generatedSnippetTitle(generatedText: String) -> String? {
  guard
    let firstLine =
      generatedText
      .split(whereSeparator: \.isNewline)
      .map({ $0.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"'`「」『』“”"))) })
      .first(where: { !$0.isEmpty })
  else {
    return nil
  }
  // 切った末尾が空白で終わらないよう、切った後にも空白を除く。
  return String(firstLine.prefix(generatedSnippetTitleMaxLength)).trimmingCharacters(in: .whitespaces)
}

/// 言語モデルが返した文字列 (カンマか改行で区切ったタグの名前) から、スニペットに付けるタグの名前を取り出す。
///
/// 返す名前は重複が無く、前後の空白・先頭の `#` と `-`・囲みの引用符を含まず、`generatedSnippetTagNameMaxLength` 文字以内で、`generatedSnippetTagLimit` 個まで。言語モデルは指示しても、箇条書き・`#` 付き・文の応答を返すことがあるため。
public func generatedSnippetTagNames(generatedText: String) -> [String] {
  var tagNames = Set<String>()
  return Array(
    generatedText
      .split(whereSeparator: { $0.isNewline || [",", "、", "，"].contains($0) })
      .map { $0.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "#-\"'`「」"))) }
      .filter { !$0.isEmpty && $0.count <= generatedSnippetTagNameMaxLength && tagNames.insert($0).inserted }
      .prefix(generatedSnippetTagLimit)
  )
}

/// 言語モデルが `sourceBody` から作ったタイトルをスニペットに付ける。付けたら `true`。保存 (`modelContext.save()`) は呼び出し側で行う。
///
/// 付けるのは、スニペットにタイトルが無く、本文が `sourceBody` のままの時だけ。言語モデルの応答を待つ間にユーザーがタイトルを付けた・本文を書き換えた時に、ユーザーの入力を上書きせず、古い本文のタイトルも付けないため。
/// `updatedAt` と更新の主体は変えない。編集を終えた後に一覧の並び (更新日時の新しい順) が変わったり、ユーザーが編集した日時が自動の処理の日時に置き換わったりしないため。
public func applyGeneratedSnippetTitle(snippet: Snippet, generatedText: String, sourceBody: String) -> Bool {
  guard snippet.title == nil, snippet.body == sourceBody, let title = generatedSnippetTitle(generatedText: generatedText) else {
    return false
  }
  snippet.title = title
  return true
}

/// 言語モデルが `sourceBody` から作ったタグをスニペットに付ける。付けたら `true`。保存 (`modelContext.save()`) は呼び出し側で行う。
///
/// 付けるのは、スニペットにタグが 1 つも無く、本文が `sourceBody` のままの時だけ (理由は `applyGeneratedSnippetTitle(snippet:generatedText:sourceBody:)` と同じ)。
/// 同じ名前のタグがあればそれを使い、無ければ作る (`resolvedTags(tagNames:modelContext:)`)。`updatedAt` と更新の主体は変えない。
public func applyGeneratedSnippetTags(snippet: Snippet, generatedText: String, sourceBody: String, modelContext: ModelContext) throws -> Bool {
  let tagNames = generatedSnippetTagNames(generatedText: generatedText)
  guard (snippet.tags ?? []).isEmpty, snippet.body == sourceBody, !tagNames.isEmpty else {
    return false
  }
  snippet.tags = try resolvedTags(tagNames: tagNames, modelContext: modelContext)
  return true
}
