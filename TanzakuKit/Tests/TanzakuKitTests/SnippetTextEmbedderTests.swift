import NaturalLanguage
import Testing

@testable import TanzakuKit

/// 意味検索に使う言語の選び方と、NLContextualEmbedding の埋め込みを確かめる。
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

  @Test(
    "モデルの最大の長さを超える文章でも、末尾の違いがベクトルに表れる",
    .enabled("NLContextualEmbedding の日本語の資産をダウンロードできる環境だけで確かめる") {
      try await requestContextualEmbeddingAssets(language: .japanese)
    }
  )
  func longTextTailAffectsVector() throws {
    let embedder = try #require(try makeContextualSnippetTextEmbedder(language: .japanese))
    let longPrefix = String(repeating: "ダミーの長い前置きの文章です。", count: 200)

    #expect(try embedder.vector(longPrefix + "猫の写真を送ってください。") != embedder.vector(longPrefix + "明日の会議を延期します。"))
  }
}
