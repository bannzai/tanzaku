import Observation
import TanzakuKit

/// スニペットグループのメニューの状態。キーワードを打つたびに入れ替え、閉じたら空にする。
@Observable
final class SnippetGroupMenuState {
  /// メニューを出しているスニペットグループ。閉じている時は `nil`。
  var snippetGroup: SnippetGroup?
  /// メニューに並べるスニペット (`snippetGroupMenuSnippets(snippetGroup:)`)。開いた時に決め、開いている間は変えない。↑↓ の位置と行を揃えるため。
  var snippets: [Snippet] = []
  /// ↑↓ で選んでいる行の `snippets` での位置。
  var selectedSnippetIndex = 0
}
