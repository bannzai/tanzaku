import SwiftUI
import TanzakuKit
import UIKit

/// スニペットの本文の編集欄。言語を選んでいる間は、入力のたびに本文全体の文字色を付け直す (`applySnippetBodyHighlight`。Mac の編集欄と同じ)。
///
/// SwiftUI の `TextEditor` は iOS 26 より前では文字ごとの色を出せないため、`UITextView` を使う。
/// Form の行が本文の長さに合わせて伸びるよう、`UITextView` 自身ではスクロールさせない。
/// 本文はコードとして貼るため、先頭の大文字化・自動修正・引用符とダッシュの置き換えはしない。
struct SnippetBodyEditor: UIViewRepresentable {
  /// 入力中の本文。
  @Binding var text: String
  /// 選んでいる言語 (`Snippet.language` の値)。`nil` はプレーンテキスト。
  var language: String?

  /// 入力を画面の状態へ返し、文字色を付けた言語と外観を覚えておく coordinator を作る。
  func makeCoordinator() -> SnippetBodyEditorCoordinator {
    SnippetBodyEditorCoordinator(text: $text, language: language)
  }

  /// 編集欄を作り、最初の文字色を付ける。背景は Form の行の色を見せるため透明にする。
  func makeUIView(context: Context) -> UITextView {
    let textView = UITextView()
    textView.delegate = context.coordinator
    // `.callout.monospaced()` (編集欄の元の `TextEditor` と詳細の本文) と同じ大きさにし、文字の大きさの設定に合わせて変える。callout の基準の大きさは 16pt。
    textView.font = UIFontMetrics(forTextStyle: .callout).scaledFont(for: .monospacedSystemFont(ofSize: 16, weight: .regular))
    textView.adjustsFontForContentSizeCategory = true
    textView.textColor = .label
    textView.backgroundColor = .clear
    textView.isScrollEnabled = false
    textView.autocapitalizationType = .none
    textView.autocorrectionType = .no
    textView.spellCheckingType = .no
    textView.smartQuotesType = .no
    textView.smartDashesType = .no
    textView.smartInsertDeleteType = .no
    textView.accessibilityLabel = String(localized: "Body")
    textView.accessibilityIdentifier = "snippet-body-editor"
    textView.text = text
    context.coordinator.colorScheme = context.environment.colorScheme
    context.coordinator.applyHighlight(textView: textView)
    return textView
  }

  /// 画面の状態の本文・言語・外観を編集欄に映す。
  func updateUIView(_ textView: UITextView, context: Context) {
    let coordinator = context.coordinator
    coordinator.text = $text
    let isTextReplaced = textView.text != text
    if isTextReplaced {
      textView.text = text
    }
    // 言語と外観が変わらない更新 (親の画面の再描画) で本文全体を付け直さないよう、変わった時だけ付け直す。入力による変更は `textViewDidChange` で付け直している。
    guard isTextReplaced || coordinator.language != language || coordinator.colorScheme != context.environment.colorScheme else {
      return
    }
    coordinator.language = language
    coordinator.colorScheme = context.environment.colorScheme
    coordinator.applyHighlight(textView: textView)
  }

  /// 提案された幅で本文を全部出せる高さにする。Form の行を本文の長さに合わせて伸ばすため。
  func sizeThatFits(_ proposal: ProposedViewSize, uiView textView: UITextView, context: Context) -> CGSize? {
    guard let width = proposal.width else {
      return nil
    }
    return CGSize(width: width, height: textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
  }
}

/// 本文の編集欄の入力を受け取り、画面の状態へ返してハイライトを付け直す。`UITextView` の delegate が `NSObject` を要るため class にする。
final class SnippetBodyEditorCoordinator: NSObject, UITextViewDelegate {
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
  func textViewDidChange(_ textView: UITextView) {
    text.wrappedValue = textView.text
    applyHighlight(textView: textView)
  }

  /// 本文全体の文字色を今の言語と外観で付け直す。日本語の変換中は変換中の文字を崩さないよう付け直さず、確定した時の `textViewDidChange` で付け直す。
  func applyHighlight(textView: UITextView) {
    guard textView.markedTextRange == nil else {
      return
    }
    applySnippetBodyHighlight(textStorage: textView.textStorage, language: language, colorScheme: colorScheme)
  }
}
