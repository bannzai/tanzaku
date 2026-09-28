import SwiftUI
import TanzakuKit

extension SnippetColor {
  /// 色の帯に塗る色。ライトとダークの値は `documents/design/Manager.dc.html` の `band` の値で、`Assets.xcassets` の `Band*` の色に持つ。
  var bandColor: Color {
    switch self {
    case .shu:
      Color("BandShu")
    case .ai:
      Color("BandAi")
    case .matsuba:
      Color("BandMatsuba")
    case .yamabuki:
      Color("BandYamabuki")
    case .murasaki:
      Color("BandMurasaki")
    }
  }

  /// 色の名前。色の選択のボタンの読み上げと、選んだ色の表示に使う。
  var label: LocalizedStringKey {
    switch self {
    case .shu:
      "Vermilion"
    case .ai:
      "Indigo"
    case .matsuba:
      "Pine green"
    case .yamabuki:
      "Golden yellow"
    case .murasaki:
      "Purple"
    }
  }
}
