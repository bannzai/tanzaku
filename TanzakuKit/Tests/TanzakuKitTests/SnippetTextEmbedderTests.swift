import NaturalLanguage
import Testing

@testable import TanzakuKit

/// 意味検索に使う言語の選び方を確かめる。
struct SnippetTextEmbedderTests {
  @Test(
    "端末の優先言語の言語コードを使い、無ければ英語にする",
    arguments: [
      (["ja-JP", "en-US"], "ja"),
      (["en-US"], "en"),
      (["fr"], "fr"),
      ([], "en"),
    ] as [([String], String)]
  )
  func embeddingLanguageFollowsPreferredLanguages(preferredLanguages: [String], expectedLanguageRawValue: String) {
    #expect(snippetEmbeddingLanguage(preferredLanguages: preferredLanguages).rawValue == expectedLanguageRawValue)
  }
}
