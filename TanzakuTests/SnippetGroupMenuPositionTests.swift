import CoreGraphics
import Testing

@testable import Tanzaku

/// スニペットグループのメニューのパネルを出す位置を確かめる。
struct SnippetGroupMenuPositionTests {
  /// 主画面 (1440 x 900) の Dock・メニューバーを除いた範囲。
  private let visibleFrame = CGRect(x: 0, y: 80, width: 1440, height: 795)
  /// メニューの大きさ。
  private let menuSize = CGSize(width: 320, height: 200)

  @Test("キャレットが取れた時は、Quartz の座標を AppKit の座標に直してキャレットの下に出す")
  func placesBelowCaret() {
    // Quartz の y = 300〜318 のキャレットは、AppKit の座標では y = 582〜600。
    let origin = snippetGroupMenuOrigin(
      caretRect: CGRect(x: 400, y: 300, width: 0, height: 18),
      mouseLocation: CGPoint(x: 10, y: 10),
      menuSize: menuSize,
      primaryScreenHeight: 900,
      visibleFrame: visibleFrame
    )

    #expect(origin == CGPoint(x: 400, y: 582 - 4 - 200))
  }

  @Test("キャレットの下で画面からはみ出す時は、キャレットの上に出す")
  func placesAboveCaretNearBottom() {
    // Quartz の y = 700〜718 のキャレットは、AppKit の座標では y = 182〜200。下に出すと y = -22 で画面の下にはみ出す。
    let origin = snippetGroupMenuOrigin(
      caretRect: CGRect(x: 400, y: 700, width: 0, height: 18),
      mouseLocation: CGPoint(x: 10, y: 10),
      menuSize: menuSize,
      primaryScreenHeight: 900,
      visibleFrame: visibleFrame
    )

    #expect(origin == CGPoint(x: 400, y: 200 + 4))
  }

  @Test("キャレットが取れない時は、マウスポインタの下に出す")
  func placesBelowMouseWithoutCaret() {
    let origin = snippetGroupMenuOrigin(
      caretRect: nil,
      mouseLocation: CGPoint(x: 500, y: 600),
      menuSize: menuSize,
      primaryScreenHeight: 900,
      visibleFrame: visibleFrame
    )

    #expect(origin == CGPoint(x: 500, y: 600 - 4 - 200))
  }

  @Test("画面の右端からはみ出す時は、右端に揃える")
  func clampsToRightEdge() {
    let origin = snippetGroupMenuOrigin(
      caretRect: nil,
      mouseLocation: CGPoint(x: 1400, y: 600),
      menuSize: menuSize,
      primaryScreenHeight: 900,
      visibleFrame: visibleFrame
    )

    #expect(origin.x == 1440 - 320)
  }
}
