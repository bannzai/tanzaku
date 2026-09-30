import SwiftUI
import TanzakuKit
import UIKit

/// ライトとダークで値を切り替える色。色の帯は macOS のデザインの値 (`documents/design/Manager.dc.html` の LIGHT / DARK の band) に合わせるため、システムの色ではなくこれで作る。
///
/// UIKit は色を解決する時に `dynamicProvider` をメインスレッド以外からも呼び得るため、閉包が MainActor に隔離されないよう nonisolated にする。
nonisolated func appearanceAdaptiveColor(lightHex: UInt32, darkHex: UInt32) -> Color {
  Color(
    uiColor: UIColor { traitCollection in
      let hex = traitCollection.userInterfaceStyle == .dark ? darkHex : lightHex
      return UIColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
      )
    }
  )
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

/// スニペットの色の帯 (幅 4pt)。色が無いスニペットは帯を出さず、幅だけ空けて名前の位置を揃える (`documents/DIRECTION.md`「決めたこと」)。
struct SnippetColorBand: View {
  /// 帯のスニペット。
  var snippet: Snippet

  var body: some View {
    RoundedRectangle(cornerRadius: 2)
      .fill(snippet.color.map { snippetBandColor(snippetColor: $0) } ?? .clear)
      .frame(width: 4)
  }
}
