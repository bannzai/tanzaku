/// 本文のシンタックスハイライトの言語。`Snippet.language` に raw value を入れ、`nil` はプレーンテキスト。
///
/// raw value は同期するストアに入り、本番の CloudKit スキーマに残るため変えない。言語を足す時は case を足す。
/// 並びは編集画面の Picker に出す順で、スニペットに入れる本文 (コマンド・設定・プロンプト) で使うことが多いものを先に置く。
public enum SnippetLanguage: String, CaseIterable, Sendable {
  /// シェル (bash・zsh)。
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
  /// Go。
  case go
  /// Ruby。
  case ruby
  /// HTML。
  case html
  /// CSS。
  case css

  /// 画面に出す言語の名前。言語の固有名で、翻訳しない。
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
    case .go:
      "Go"
    case .ruby:
      "Ruby"
    case .html:
      "HTML"
    case .css:
      "CSS"
    }
  }
}
