/// スニペットの色の帯の色 (`documents/DIRECTION.md`「決めたこと」の 5 色)。`Snippet.colorRawValue` に raw value を入れる。
///
/// raw value は同期するストアに入り、本番の CloudKit スキーマに残るため変えない。表示の色 (ライト・ダーク) は各アプリが持つ。
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
