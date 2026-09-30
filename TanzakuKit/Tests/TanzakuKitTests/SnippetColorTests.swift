import Foundation
import Testing

@testable import TanzakuKit

/// `Snippet.color` の raw value からの読み取りを確かめる。
struct SnippetColorTests {
  @Test("知っている raw value は色にし、無い値と知らない値は色なしにする", arguments: [("ai", SnippetColor.ai), (nil, nil), ("unknown", nil)] as [(String?, SnippetColor?)])
  func colorIsReadFromRawValue(colorRawValue: String?, color: SnippetColor?) {
    let snippet = Snippet(body: "echo dummy")
    snippet.colorRawValue = colorRawValue

    #expect(snippet.color == color)
  }
}
