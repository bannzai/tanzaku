import Foundation
import Highlightr
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// ライト・ダークごとにテーマを設定した Highlightr。`nil` は highlight.js を読み込めなかったことを表し、その時は本文をハイライトせずに出す。
///
/// highlight.js (約 1 MB) の読み込みに時間がかかるため、テーマごとに 1 度だけ作り、最初にハイライトする時まで作らない (アプリの起動を遅らせない)。
/// Highlightr は JavaScriptCore を同期で呼ぶため、メインアクターに閉じる。
@MainActor private var snippetHighlightrs: [ColorScheme: Highlightr?] = [:]

/// Highlightr が持つ highlight.js の言語名。言語の Picker を描くたびに JavaScriptCore を呼ばないよう、1 度だけ取る。
@MainActor private var cachedSnippetHighlightLanguageNames: [String]?

/// ハイライトに使う highlight.js のテーマの名前。
///
/// StackOverflow のライト・ダークは、本文の背景 (`documents/design/` の code の色と iOS の Form の行の色) に対してどの文字色もコントラスト比 4.5 (WCAG AA) 以上で、
/// キーワード・文字列・数値・属性の色相が色の帯の藍・松葉・朱・紫に近いため。コントラスト比は `SnippetBodyHighlightTests` で確かめる。
func snippetHighlightThemeName(colorScheme: ColorScheme) -> String {
  colorScheme == .dark ? "stackoverflow-dark" : "stackoverflow-light"
}

/// テーマを設定した Highlightr。
@MainActor
private func snippetHighlightr(colorScheme: ColorScheme) -> Highlightr? {
  if let cachedHighlightr = snippetHighlightrs[colorScheme] {
    return cachedHighlightr
  }
  let highlightr = Highlightr()
  highlightr?.setTheme(to: snippetHighlightThemeName(colorScheme: colorScheme))
  // スニペットは書きかけのコードや断片が多い。highlight.js は文法に合わない字句を見つけると本文全体の色を外すため、見つけても色を付け続ける。
  highlightr?.ignoreIllegals = true
  // 読み込めなかったことも覚え、ハイライトのたびに highlight.js を読み込み直さないよう `.some(nil)` で入れる。
  snippetHighlightrs[colorScheme] = .some(highlightr)
  return highlightr
}

/// Highlightr が持つ highlight.js の言語名 (`hljs.listLanguages()`)。言語の Picker の選択肢と、`Snippet.language` の値の確かめに使う。
@MainActor
public func snippetHighlightLanguageNames() -> [String] {
  if let cachedSnippetHighlightLanguageNames {
    return cachedSnippetHighlightLanguageNames
  }
  let highlightLanguageNames = snippetHighlightr(colorScheme: .light)?.supportedLanguages() ?? []
  cachedSnippetHighlightLanguageNames = highlightLanguageNames
  return highlightLanguageNames
}

/// 本文を highlight.js でハイライトした文字列。プレーンテキスト・highlight.js が持たない言語・ハイライトできなかった本文は `nil`。
///
/// Highlightr はテーマのフォント (Courier) も付けるが、使うのは文字色だけにする。フォントは表示する側の等幅のフォントにそろえるため。
@MainActor
func highlightedSnippetBodyAttributedString(body: String, language: String?, colorScheme: ColorScheme) -> NSAttributedString? {
  guard
    let highlightLanguageName = snippetHighlightLanguageName(language: language, highlightLanguageNames: snippetHighlightLanguageNames()),
    let highlightedBody = snippetHighlightr(colorScheme: colorScheme)?.highlight(body, as: highlightLanguageName),
    // Highlightr は HTML の文字参照を文字に戻して組み立てる。本文と違う文字を出さないよう、本文と一致しない時はハイライトしない。
    highlightedBody.string == body
  else {
    return nil
  }
  return highlightedBody
}

/// 本文の表示 (ランチャーのプレビュー・iOS の詳細) に出す文字列。言語を選んでいる時は highlight.js の文字色を付け、プレーンテキストは色を付けない。
@MainActor
public func highlightedSnippetBody(body: String, language: String?, colorScheme: ColorScheme) -> AttributedString {
  guard let highlightedBody = highlightedSnippetBodyAttributedString(body: body, language: language, colorScheme: colorScheme) else {
    return AttributedString(body)
  }
  var attributedBody = AttributedString()
  highlightedBody.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: highlightedBody.length)) { highlightColor, range, _ in
    var bodyRun = AttributedString((highlightedBody.string as NSString).substring(with: range))
    if let highlightColor = highlightColor as? RPColor {
      #if os(macOS)
      bodyRun.foregroundColor = Color(nsColor: highlightColor)
      #else
      bodyRun.foregroundColor = Color(uiColor: highlightColor)
      #endif
    }
    attributedBody.append(bodyRun)
  }
  return attributedBody
}

/// 編集欄の本文の文字色を付け直す。言語を選んでいる時は highlight.js の文字色にし、プレーンテキストは文字の既定の色に戻す (前に選んでいた言語の色を消すため)。
///
/// フォントは変えず、編集欄の等幅のフォントのままにする。日本語の変換中 (未確定の文字がある間) は呼ばない。文字の属性を変えると変換中の文字が崩れるため、呼ぶ側で止める。
@MainActor
public func applySnippetBodyHighlight(textStorage: NSTextStorage, language: String?, colorScheme: ColorScheme) {
  let bodyRange = NSRange(location: 0, length: textStorage.length)
  textStorage.beginEditing()
  #if os(macOS)
  textStorage.addAttribute(.foregroundColor, value: NSColor.textColor, range: bodyRange)
  #else
  textStorage.addAttribute(.foregroundColor, value: UIColor.label, range: bodyRange)
  #endif
  highlightedSnippetBodyAttributedString(body: textStorage.string, language: language, colorScheme: colorScheme)?
    .enumerateAttribute(.foregroundColor, in: bodyRange) { highlightColor, range, _ in
      if let highlightColor {
        textStorage.addAttribute(.foregroundColor, value: highlightColor, range: range)
      }
    }
  textStorage.endEditing()
}
