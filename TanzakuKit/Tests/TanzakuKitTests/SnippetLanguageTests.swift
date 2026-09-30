import Testing

@testable import TanzakuKit

/// `Snippet.language` の値と highlight.js の言語名の対応と、言語の Picker の選択肢の組み立てを確かめる。
struct SnippetLanguageTests {
  /// highlight.js が持つ言語名の見本。`bash` / `shell` / `xml` は `SnippetLanguage` の言語と重なる名前、`plaintext` は色を付けない言語、`rust` / `cpp` / `awk` は重ならない名前。
  let highlightLanguageNames = ["rust", "bash", "shell", "swift", "xml", "plaintext", "cpp", "yaml", "awk"]

  @Test("Picker の 2 つ目の欄は、先頭の欄の言語・raw value と同じ名前・plaintext を除いて名前の順に並べる")
  func pickerOtherLanguageNamesExcludeSnippetLanguages() {
    #expect(snippetLanguagePickerOtherLanguageNames(highlightLanguageNames: highlightLanguageNames) == ["awk", "cpp", "rust"])
  }

  @Test("Picker の 2 つ目の欄の値は、先頭の欄の値と重ならない")
  func pickerOtherLanguageNamesDoNotCollideWithSnippetLanguages() {
    let otherLanguageNames = Set(snippetLanguagePickerOtherLanguageNames(highlightLanguageNames: highlightLanguageNames))

    #expect(otherLanguageNames.isDisjoint(with: SnippetLanguage.allCases.map(\.rawValue)))
    #expect(otherLanguageNames.isDisjoint(with: SnippetLanguage.allCases.map(\.highlightLanguageName)))
  }

  @Test(
    "Snippet.language の値を highlight.js の言語名にし、プレーンテキストと highlight.js が持たない名前はハイライトしない",
    arguments: [
      ("shell", "bash"), ("html", "xml"), ("swift", "swift"), ("rust", "rust"), (nil, nil), ("plaintext", nil), ("dummy-unknown-language", nil),
    ] as [(String?, String?)]
  )
  func highlightLanguageNameIsResolved(language: String?, highlightLanguageName: String?) {
    #expect(snippetHighlightLanguageName(language: language, highlightLanguageNames: highlightLanguageNames) == highlightLanguageName)
  }

  @Test(
    "編集画面の Picker はハイライトできる値だけを選んでおき、それ以外はプレーンテキストにする",
    arguments: [("shell", "shell"), ("rust", "rust"), (nil, nil), ("dummy-unknown-language", nil)] as [(String?, String?)]
  )
  func pickerSelectionKeepsOnlyHighlightableLanguages(language: String?, pickerSelection: String?) {
    #expect(snippetLanguagePickerSelection(language: language, highlightLanguageNames: highlightLanguageNames) == pickerSelection)
  }

  @Test("表示名は先頭の欄の言語は名前、それ以外は highlight.js の言語名にする", arguments: [("shell", "Shell"), ("html", "HTML"), ("rust", "rust")])
  func displayNameUsesSnippetLanguageOrHighlightLanguageName(language: String, displayName: String) {
    #expect(snippetLanguageDisplayName(language: language) == displayName)
  }
}
