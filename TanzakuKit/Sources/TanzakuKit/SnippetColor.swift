import Foundation

/// スニペットの色の帯の色。`Snippet.colorRawValue` にこの raw value を入れる。
///
/// 短冊のモチーフの 5 色に限る (`documents/DIRECTION.md`「デザインの方向」「決めたこと」)。raw value は同期するストアに残るため、変えない。
public enum SnippetColor: String, CaseIterable, Sendable {
  /// 朱。
  case shu
  /// 藍。
  case ai
  /// 松葉。
  case matsuba
  /// 山吹。
  case yamabuki
  /// 紫。
  case murasaki
}

extension Snippet {
  /// 色の帯の色。raw value が無いか、知らない値 (新しい版のアプリが足した色) の時は色なしとして扱う。
  public var color: SnippetColor? {
    colorRawValue.flatMap(SnippetColor.init(rawValue:))
  }
}
