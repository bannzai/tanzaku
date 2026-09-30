import AppKit
import Foundation
import Highlightr
import SwiftUI
import Testing

@testable import TanzakuKit

/// 本文のハイライトの有無と、ハイライトの色の読みやすさを確かめる。Highlightr (JavaScriptCore) を実際に動かす。
@MainActor
struct SnippetBodyHighlightTests {
  /// 言語ごとの本文の見本。秘匿情報を入れないよう偽の値だけにする (`.claude/rules/snippet-content-handling.md`)。
  let sampleBodies: [SnippetLanguage: String] = [
    .shell: "# dummy\nexport API_TOKEN=\"${API_TOKEN:-dummy-token}\"\ncurl -sS -H \"Authorization: Bearer ${API_TOKEN}\" https://example.com/v1 | jq '.items[0]'",
    .yaml: "# dummy\njobs:\n  deploy:\n    runs-on: ubuntu-latest\n    timeout-minutes: 30\n    env:\n      API_TOKEN: ${{ secrets.API_TOKEN }}\n    enabled: true",
    .json: "{\"name\": \"dummy\", \"count\": 3, \"enabled\": true, \"items\": [null, 1.5]}",
    .markdown: "# Dummy\n\n- **bold** and _italic_\n- `code` and [link](https://example.com)\n\n```sh\necho dummy\n```",
    .sql: "-- dummy\nSELECT id, name FROM snippets WHERE count > 3 AND name = 'dummy' ORDER BY id LIMIT 10;",
    .swift: "// dummy\n@MainActor\nstruct Dummy: View {\n  let count: Int = 3\n  var body: some View { Text(\"dummy \\(count)\") }\n}",
    .python: "# dummy\n@dataclass\nclass Dummy:\n    count: int = 3\n    def run(self) -> str:\n        return f\"dummy {self.count}\" if True else None",
    .javascript: "// dummy\nconst dummy = async (count = 3) => {\n  const items = [1, 2, null];\n  return `dummy ${count}` + /re/g.source;\n};",
    .typescript: "// dummy\ninterface Dummy { count: number }\nexport function run(dummy: Dummy): string {\n  return `dummy ${dummy.count}`;\n}",
    .ruby: "# dummy\nclass Dummy < Base\n  def run(count = 3)\n    puts \"dummy #{count}\" if count > 0\n    :symbol\n  end\nend",
    .go: "// dummy\npackage main\n\nfunc run(count int) string {\n\treturn fmt.Sprintf(\"dummy %d\", count+3)\n}",
    .html: "<!DOCTYPE html>\n<!-- dummy -->\n<div class=\"dummy\" id=\"main\" data-count=\"3\">\n  <a href=\"https://example.com\">dummy</a>\n</div>",
    .css: "/* dummy */\n.dummy > #main:hover {\n  color: #2e4f86;\n  margin: 3px 0 !important;\n}\n@media (max-width: 600px) { .dummy { display: none; } }",
  ]

  @Test("先頭の欄の言語は、どれも Highlightr が持つ highlight.js の言語名にする")
  func snippetLanguagesAreSupportedByHighlightr() {
    let highlightLanguageNames = snippetHighlightLanguageNames()

    for snippetLanguage in SnippetLanguage.allCases {
      #expect(highlightLanguageNames.contains(snippetLanguage.highlightLanguageName), "\(snippetLanguage)")
    }
  }

  @Test("Picker の選択肢は highlight.js の言語を並べ、値が重ならない")
  func pickerChoicesComeFromHighlightJS() {
    let otherLanguageNames = snippetLanguagePickerOtherLanguageNames(highlightLanguageNames: snippetHighlightLanguageNames())
    let pickerLanguageNames = SnippetLanguage.allCases.map(\.rawValue) + otherLanguageNames

    // Highlightr 2.3.0 の highlight.js 11.11.1 は 192 の言語を持ち、先頭の欄と重なる 14 と plaintext を除くと 177 になる。多数の言語を並べる決まり (documents/DIRECTION.md「決めたこと」) を満たすことを見る。
    #expect(otherLanguageNames.count > 150)
    #expect(Set(pickerLanguageNames).count == pickerLanguageNames.count)
    #expect(otherLanguageNames.allSatisfy { snippetHighlightLanguageName(language: $0, highlightLanguageNames: snippetHighlightLanguageNames()) == $0 })
  }

  @Test("プレーンテキストと highlight.js が持たない言語はハイライトしない", arguments: [nil, "dummy-unknown-language"] as [String?])
  func plainTextIsNotHighlighted(language: String?) {
    let body = "let dummy = \"value\" // 3"

    #expect(highlightedSnippetBodyAttributedString(body: body, language: language, colorScheme: .light) == nil)
    let attributedBody = highlightedSnippetBody(body: body, language: language, colorScheme: .light)
    #expect(String(attributedBody.characters) == body)
    #expect(attributedBody.runs.allSatisfy { run in (run.foregroundColor as Color?) == nil })
  }

  @Test("言語を選んだ本文は、本文の文字を変えずに複数の文字色でハイライトする", arguments: SnippetLanguage.allCases)
  func selectedLanguageIsHighlighted(snippetLanguage: SnippetLanguage) throws {
    let body = try #require(sampleBodies[snippetLanguage])

    for colorScheme in [ColorScheme.light, .dark] {
      let highlightedBody = try #require(highlightedSnippetBodyAttributedString(body: body, language: snippetLanguage.rawValue, colorScheme: colorScheme))
      #expect(highlightedBody.string == body)
      #expect(foregroundColorHexes(attributedString: highlightedBody).count >= 2, "\(snippetLanguage) \(colorScheme)")

      let attributedBody = highlightedSnippetBody(body: body, language: snippetLanguage.rawValue, colorScheme: colorScheme)
      #expect(String(attributedBody.characters) == body)
      #expect(Set(attributedBody.runs.compactMap { run in run.foregroundColor as Color? }).count >= 2)
    }
  }

  @Test("highlight.js の言語名で保存した本文もハイライトする")
  func highlightLanguageNameIsHighlighted() throws {
    let body = "fn main() {\n    let dummy = 3;\n    println!(\"dummy {}\", dummy);\n}"

    let highlightedBody = try #require(highlightedSnippetBodyAttributedString(body: body, language: "rust", colorScheme: .light))
    #expect(foregroundColorHexes(attributedString: highlightedBody).count >= 2)
  }

  @Test("編集欄の文字色は、言語を選ぶとハイライトの色にし、プレーンテキストに戻すと既定の色に戻す")
  func editorHighlightIsAppliedAndCleared() throws {
    let body = try #require(sampleBodies[.swift])
    let textStorage = NSTextStorage(string: body, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)])

    applySnippetBodyHighlight(textStorage: textStorage, language: SnippetLanguage.swift.rawValue, colorScheme: .light)
    #expect(foregroundColorHexes(attributedString: textStorage).count >= 2)

    applySnippetBodyHighlight(textStorage: textStorage, language: nil, colorScheme: .light)
    var plainTextColors: [NSColor] = []
    textStorage.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: textStorage.length)) { foregroundColor, _, _ in
      if let foregroundColor = foregroundColor as? NSColor {
        plainTextColors.append(foregroundColor)
      }
    }
    #expect(plainTextColors == [NSColor.textColor])
    // フォントは編集欄のものを残す (Highlightr のテーマの Courier にしない)。
    #expect((textStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont) == NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))
  }

  @Test(
    "ハイライトの文字色は、どれも本文の背景に対してコントラスト比 4.5 (WCAG AA) 以上にする",
    arguments: [
      // Mac の管理ウィンドウの本文とランチャーのプレビューの背景 (documents/design/ の code の色)、iOS の Form の行の背景。
      (ColorScheme.light, [0xF6F7F9, 0xF5F6F8, 0xFFFFFF] as [UInt32]),
      (ColorScheme.dark, [0x19191B, 0x1B1B1D, 0x1C1C1E] as [UInt32]),
    ]
  )
  func highlightColorsAreReadable(colorScheme: ColorScheme, backgroundHexes: [UInt32]) throws {
    for (snippetLanguage, body) in sampleBodies {
      let highlightedBody = try #require(highlightedSnippetBodyAttributedString(body: body, language: snippetLanguage.rawValue, colorScheme: colorScheme))
      for foregroundColorHex in foregroundColorHexes(attributedString: highlightedBody) {
        for backgroundHex in backgroundHexes {
          let foregroundContrastRatio = contrastRatio(foregroundHex: foregroundColorHex, backgroundHex: backgroundHex)
          #expect(
            foregroundContrastRatio >= 4.5,
            "\(snippetLanguage) \(colorScheme): #\(String(foregroundColorHex, radix: 16)) on #\(String(backgroundHex, radix: 16)) = \(foregroundContrastRatio)"
          )
        }
      }
    }
  }

  @Test("highlight.js の読み込みは、最初にハイライトする時の待ち時間として 1 秒未満にする")
  func highlightrLoadsQuickly() {
    let loadDuration = ContinuousClock().measure {
      _ = Highlightr()
    }

    // 最初の言語の選択・プレビューの時にだけかかる時間。CI のログで実測を残す。
    print("Highlightr の読み込み: \(loadDuration)")
    #expect(loadDuration < .seconds(1))
  }

  /// 文字列に付いた文字色の sRGB の値 (0xRRGGBB)。
  private func foregroundColorHexes(attributedString: NSAttributedString) -> Set<UInt32> {
    var foregroundColorHexes: Set<UInt32> = []
    attributedString.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: attributedString.length)) { foregroundColor, _, _ in
      guard let srgbColor = (foregroundColor as? NSColor)?.usingColorSpace(.sRGB) else {
        return
      }
      foregroundColorHexes.insert(
        UInt32((srgbColor.redComponent * 255).rounded()) << 16 | UInt32((srgbColor.greenComponent * 255).rounded()) << 8
          | UInt32((srgbColor.blueComponent * 255).rounded())
      )
    }
    return foregroundColorHexes
  }

  /// WCAG 2.x のコントラスト比 ( https://www.w3.org/TR/WCAG21/#dfn-contrast-ratio )。
  private func contrastRatio(foregroundHex: UInt32, backgroundHex: UInt32) -> Double {
    let foregroundLuminance = relativeLuminance(hex: foregroundHex)
    let backgroundLuminance = relativeLuminance(hex: backgroundHex)
    return (max(foregroundLuminance, backgroundLuminance) + 0.05) / (min(foregroundLuminance, backgroundLuminance) + 0.05)
  }

  /// WCAG 2.x の相対輝度 ( https://www.w3.org/TR/WCAG21/#dfn-relative-luminance )。
  private func relativeLuminance(hex: UInt32) -> Double {
    let linearComponents = [(hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF].map { component in
      let srgbComponent = Double(component) / 255
      return srgbComponent <= 0.03928 ? srgbComponent / 12.92 : pow((srgbComponent + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linearComponents[0] + 0.7152 * linearComponents[1] + 0.0722 * linearComponents[2]
  }
}
