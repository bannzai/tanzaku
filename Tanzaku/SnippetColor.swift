import AppKit
import SwiftUI

/// スニペットの色の帯の色 (`Snippet.colorRawValue`)。短冊のモチーフの 5 色 (`documents/DIRECTION.md`「デザインの方向」)。
enum SnippetColor: String, CaseIterable {
  /// 朱。
  case shu
  /// 藍。アプリのアイコンの短冊の色でもある。
  case ai
  /// 松葉。
  case matsuba
  /// 山吹。
  case yamabuki
  /// 紫。
  case murasaki

  /// 帯の色。ライトとダークの値は `documents/design/*.dc.html` の `band` の値。
  var color: Color {
    switch self {
    case .shu:
      appearanceAdaptiveColor(lightHex: 0xD2452C, darkHex: 0xE4634A)
    case .ai:
      appearanceAdaptiveColor(lightHex: 0x2E4F86, darkHex: 0x6F92CC)
    case .matsuba:
      appearanceAdaptiveColor(lightHex: 0x3E7A4B, darkHex: 0x6BAF78)
    case .yamabuki:
      appearanceAdaptiveColor(lightHex: 0xD39A1C, darkHex: 0xE6B84A)
    case .murasaki:
      appearanceAdaptiveColor(lightHex: 0x74509A, darkHex: 0xA585CC)
    }
  }
}

/// 外観 (ライト・ダーク) に合わせて切り替わる色。
func appearanceAdaptiveColor(lightHex: UInt32, darkHex: UInt32) -> Color {
  Color(
    // 描画のスレッドから呼ばれることがあり、メインアクターに隔離しないため @Sendable にする。
    nsColor: NSColor(name: nil) { @Sendable appearance in
      let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? darkHex : lightHex
      return NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
      )
    }
  )
}
