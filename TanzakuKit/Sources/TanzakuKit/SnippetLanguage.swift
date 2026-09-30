import Foundation

/// 言語の Picker の先頭の欄に出す、よく使う言語。`Snippet.language` にこの raw value を入れ、`nil` はプレーンテキスト (ハイライトなし) を表す。
/// ここに無い言語は highlight.js の言語名をそのまま `Snippet.language` に入れる (`snippetLanguagePickerOtherLanguageNames(highlightLanguageNames:)`)。
///
/// 並びは編集画面の Picker に出す順。スニペットに入れる本文として多いシェル・設定ファイル・スクリプトを先に置く。raw value は同期するストアに残るため、変えない。
public enum SnippetLanguage: String, CaseIterable, Sendable {
  /// シェル。
  case shell
  /// YAML。
  case yaml
  /// JSON。
  case json
  /// Markdown。
  case markdown
  /// SQL。
  case sql
  /// Swift。
  case swift
  /// Python。
  case python
  /// JavaScript。
  case javascript
  /// TypeScript。
  case typescript
  /// Ruby。
  case ruby
  /// Go。
  case go
  /// HTML。
  case html
  /// CSS。
  case css

  /// Picker に出す名前。言語名は固有名詞で、どのロケールでも同じ表記のため翻訳しない。
  public var displayName: String {
    switch self {
    case .shell:
      "Shell"
    case .yaml:
      "YAML"
    case .json:
      "JSON"
    case .markdown:
      "Markdown"
    case .sql:
      "SQL"
    case .swift:
      "Swift"
    case .python:
      "Python"
    case .javascript:
      "JavaScript"
    case .typescript:
      "TypeScript"
    case .ruby:
      "Ruby"
    case .go:
      "Go"
    case .html:
      "HTML"
    case .css:
      "CSS"
    }
  }

  /// ハイライトに使う highlight.js の言語名。
  ///
  /// `shell` は highlight.js ではプロンプト (`$ `) 付きの実行記録 (Shell Session) の名前で、プロンプトの無いコマンドには色が付かないため、シェルスクリプトの `bash` にする。
  /// `html` は highlight.js では `xml` の別名のため、`listLanguages()` が返す名前の `xml` にそろえる。
  public var highlightLanguageName: String {
    switch self {
    case .shell:
      "bash"
    case .html:
      "xml"
    case .yaml, .json, .markdown, .sql, .swift, .python, .javascript, .typescript, .ruby, .go, .css:
      rawValue
    }
  }
}

/// `Snippet.language` の値をハイライトに使う highlight.js の言語名にする。`nil` (プレーンテキスト) はハイライトしないため `nil`。
///
/// 言語の Picker に並ばない値 (MCP から渡された highlight.js が持たない名前など) も `nil` にしてハイライトしない。知らない名前をそのまま Highlightr に渡すと、
/// Highlightr は言語を推測して色を付け、選んだ言語と違う色になるため。
public func snippetHighlightLanguageName(language: String?, highlightLanguageNames: [String]) -> String? {
  guard let language else {
    return nil
  }
  if let snippetLanguage = SnippetLanguage(rawValue: language) {
    return snippetLanguage.highlightLanguageName
  }
  return snippetLanguagePickerOtherLanguageNames(highlightLanguageNames: highlightLanguageNames).contains(language) ? language : nil
}

/// 言語の Picker の 2 つ目の欄に並べる highlight.js の言語名。先頭の欄 (`SnippetLanguage`) の言語を除き、名前の順に並べる。
///
/// `SnippetLanguage` の raw value と同じ名前も除く。`shell` のように highlight.js では別の言語 (Shell Session) を指す名前を並べると、
/// 保存した `Snippet.language` の値がどちらの言語かを区別できなくなるため。
/// highlight.js の `plaintext` も除く。色を付けない言語で、Picker の「プレーンテキスト」(`nil`) と同じになるため。
public func snippetLanguagePickerOtherLanguageNames(highlightLanguageNames: [String]) -> [String] {
  let excludedLanguageNames = Set(SnippetLanguage.allCases.flatMap { [$0.rawValue, $0.highlightLanguageName] } + ["plaintext"])
  return highlightLanguageNames.filter { !excludedLanguageNames.contains($0) }.sorted()
}

/// 編集画面の言語の Picker で最初に選んでおく値。Picker に並ばない値 (highlight.js が持たない名前など) はプレーンテキストの `nil` にする。
/// Picker の選択肢に無い値を選ばせると、何も選んでいない表示になるため。
public func snippetLanguagePickerSelection(language: String?, highlightLanguageNames: [String]) -> String? {
  snippetHighlightLanguageName(language: language, highlightLanguageNames: highlightLanguageNames) == nil ? nil : language
}

/// 言語の表示名。先頭の欄の言語は `SnippetLanguage.displayName`、それ以外は highlight.js の言語名をそのまま出す。
/// Highlightr の公開 API は highlight.js の表示名 (`hljs.getLanguage(name).name`) を返さず、言語名は Markdown のコードブロックに書く名前として開発者が読めるため。
public func snippetLanguageDisplayName(language: String) -> String {
  SnippetLanguage(rawValue: language)?.displayName ?? language
}
