import SwiftUI
import TanzakuKit

extension SnippetColor {
  /// 色の名前。色の選択のボタンの読み上げと、選んだ色の表示に使う。色の帯に塗る色は `snippetBandColor(snippetColor:)` が持つ。
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
