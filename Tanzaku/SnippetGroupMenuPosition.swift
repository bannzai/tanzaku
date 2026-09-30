import CoreGraphics

/// メニューのパネルとキャレット・マウスポインタの間の隙間。キャレットの行の文字にメニューの縁を重ねないため、macOS の補完の候補と同じくらい (数 pt) 空ける。
private let snippetGroupMenuCaretGap: CGFloat = 4

/// スニペットグループのメニューのパネルの左下の位置 (AppKit の座標。原点は主画面の左下)。
///
/// `caretRect` はアクセシビリティ API で取った入力欄のキャレットの矩形で、Quartz の座標 (原点は主画面の左上、y は下向き)。`primaryScreenHeight` で AppKit の座標に直す。
/// キャレットが取れない時 (`nil`) はマウスポインタの位置 (AppKit の座標) に出す。
/// キャレットの下に出し、画面の下にはみ出す時はキャレットの上に出す。入力中の行をメニューで隠さないため。左右と上下は `visibleFrame` (メニューを出す画面の Dock・メニューバーを除いた範囲) の中に収める。
func snippetGroupMenuOrigin(
  caretRect: CGRect?,
  mouseLocation: CGPoint,
  menuSize: CGSize,
  primaryScreenHeight: CGFloat,
  visibleFrame: CGRect
) -> CGPoint {
  let anchorX = caretRect?.minX ?? mouseLocation.x
  let anchorBottom = caretRect.map { primaryScreenHeight - $0.maxY } ?? mouseLocation.y
  let anchorTop = caretRect.map { primaryScreenHeight - $0.minY } ?? mouseLocation.y
  let belowY = anchorBottom - snippetGroupMenuCaretGap - menuSize.height
  let y = belowY >= visibleFrame.minY ? belowY : anchorTop + snippetGroupMenuCaretGap
  return CGPoint(
    x: min(max(anchorX, visibleFrame.minX), visibleFrame.maxX - menuSize.width),
    y: min(max(y, visibleFrame.minY), visibleFrame.maxY - menuSize.height)
  )
}
