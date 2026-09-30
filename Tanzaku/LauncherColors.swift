import AppKit
import SwiftUI
import TanzakuKit

/// ライトとダークで値を切り替える色。ランチャーの色はデザインの値 (`documents/design/Main.dc.html` の LIGHT / DARK) に合わせるため、システムの色ではなくこれで作る。
///
/// AppKit は色を描く時に `dynamicProvider` をメインスレッド以外からも呼び得るため、閉包が MainActor に隔離されないよう nonisolated にする。
nonisolated func appearanceAdaptiveColor(lightHex: UInt32, darkHex: UInt32) -> Color {
  Color(
    nsColor: NSColor(name: nil) { appearance in
      let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkHex : lightHex
      return NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
      )
    }
  )
}

/// ランチャーで使う色。値はデザインの LIGHT / DARK の同じ名前の値。
enum LauncherColors {
  /// パネルの背景。
  static let panel = appearanceAdaptiveColor(lightHex: 0xFFFFFF, darkHex: 0x252527)
  /// パネルの縁。デザインは黒 (ダークは白) の 12% の透明度で、背景に重ねた色にしている。
  static let panelLine = appearanceAdaptiveColor(lightHex: 0xE0E0E0, darkHex: 0x3F3F41)
  /// 下の操作の案内の帯の背景。
  static let footer = appearanceAdaptiveColor(lightHex: 0xF6F6F8, darkHex: 0x202022)
  /// 本文の文字。
  static let foreground = appearanceAdaptiveColor(lightHex: 0x1D1D1F, darkHex: 0xF2F2F4)
  /// 補足の文字。
  static let secondaryForeground = appearanceAdaptiveColor(lightHex: 0x56565B, darkHex: 0xAEAEB4)
  /// 見出し・件数などの控えめな文字。
  static let tertiaryForeground = appearanceAdaptiveColor(lightHex: 0x6E6E73, darkHex: 0x9A9AA0)
  /// 区切り線。
  static let line = appearanceAdaptiveColor(lightHex: 0xE4E4E7, darkHex: 0x37373A)
  /// キーワードの枠・キーの枠。
  static let strongLine = appearanceAdaptiveColor(lightHex: 0xC7C7CC, darkHex: 0x4A4A4E)
  /// 本文のプレビューの背景。
  static let code = appearanceAdaptiveColor(lightHex: 0xF5F6F8, darkHex: 0x1B1B1D)
  /// 選んでいる行の背景。
  static let selection = appearanceAdaptiveColor(lightHex: 0xE3EBF7, darkHex: 0x2C3C57)
  /// 新規作成のボタンの背景。
  static let accent = appearanceAdaptiveColor(lightHex: 0x2A5CA8, darkHex: 0x3A6BC0)
  /// キーワードの一致した部分の文字。
  static let accentText = appearanceAdaptiveColor(lightHex: 0x1F4F99, darkHex: 0x8DB5F2)
}

/// スニペットの色の帯の表示の色。値はデザインの band の値。
func snippetBandColor(snippetColor: SnippetColor) -> Color {
  switch snippetColor {
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
