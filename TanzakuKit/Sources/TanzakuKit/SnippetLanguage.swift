import Foundation

/// 本文のシンタックスハイライトの言語。`Snippet.language` にこの raw value を入れ、`nil` はプレーンテキスト (ハイライトなし) を表す。
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
}
