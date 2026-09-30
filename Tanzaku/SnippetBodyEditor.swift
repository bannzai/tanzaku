import AppKit
import SwiftUI
import TanzakuKit

/// スニペットの本文の編集欄。言語を選んでいる間は、入力のたびに本文全体の文字色を付け直す (`applySnippetBodyHighlight`)。
///
/// SwiftUI の `TextEditor` は macOS 26 より前では文字ごとの色を出せないため、`NSTextView` を使う。
/// 本文はコードとして貼るため、引用符・ダッシュの置き換えと自動の綴りの修正はしない。
struct SnippetBodyEditor: NSViewRepresentable {
  /// 入力中の本文。
  @Binding var text: String
  /// 選んでいる言語 (`Snippet.language` の値)。`nil` はプレーンテキスト。
  var language: String?

  /// 入力を画面の状態へ返し、文字色を付けた言語と外観を覚えておく coordinator を作る。
  func makeCoordinator() -> SnippetBodyEditorCoordinator {
    SnippetBodyEditorCoordinator(text: $text, language: language)
  }

  /// スクロールする編集欄を作り、最初の文字色を付ける。背景は SwiftUI 側 (デザインの code の色) を見せるため描かない。
  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSTextView.scrollableTextView()
    scrollView.drawsBackground = false
    guard let textView = scrollView.documentView as? NSTextView else {
      return scrollView
    }
    textView.delegate = context.coordinator
    textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
    textView.textColor = .textColor
    textView.drawsBackground = false
    textView.isRichText = false
    textView.allowsUndo = true
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.setAccessibilityIdentifier("snippet-body-editor")
    textView.string = text
    context.coordinator.colorScheme = context.environment.colorScheme
    context.coordinator.applyHighlight(textView: textView)
    return scrollView
  }

  /// 画面の状態の本文・言語・外観を編集欄に映す。
  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard let textView = scrollView.documentView as? NSTextView else {
      return
    }
    let coordinator = context.coordinator
    coordinator.text = $text
    let isTextReplaced = textView.string != text
    if isTextReplaced {
      textView.string = text
    }
    // 言語と外観が変わらない更新 (親の画面の再描画) で本文全体を付け直さないよう、変わった時だけ付け直す。入力による変更は `textDidChange` で付け直している。
    guard isTextReplaced || coordinator.language != language || coordinator.colorScheme != context.environment.colorScheme else {
      return
    }
    coordinator.language = language
    coordinator.colorScheme = context.environment.colorScheme
    coordinator.applyHighlight(textView: textView)
  }
}

/// 本文の編集欄の入力を受け取り、画面の状態へ返してハイライトを付け直す。`NSTextView` の delegate が `NSObject` を要るため class にする。
final class SnippetBodyEditorCoordinator: NSObject, NSTextViewDelegate {
  /// 入力中の本文。
  var text: Binding<String>
  /// 今の文字色を付けた言語。
  var language: String?
  /// 今の文字色を付けた外観。
  var colorScheme: ColorScheme = .light

  /// 入力中の本文と、最初に文字色を付ける言語を受け取る。class は memberwise initializer を持たないため書く。
  init(text: Binding<String>, language: String?) {
    self.text = text
    self.language = language
  }

  /// 入力した本文を画面の状態へ返し、文字色を付け直す。
  func textDidChange(_ notification: Notification) {
    guard let textView = notification.object as? NSTextView else {
      return
    }
    text.wrappedValue = textView.string
    applyHighlight(textView: textView)
  }

  /// 本文全体の文字色を今の言語と外観で付け直す。日本語の変換中は変換中の文字を崩さないよう付け直さず、確定した時の `textDidChange` で付け直す。
  func applyHighlight(textView: NSTextView) {
    guard !textView.hasMarkedText(), let textStorage = textView.textStorage else {
      return
    }
    applySnippetBodyHighlight(textStorage: textStorage, language: language, colorScheme: colorScheme)
  }
}
