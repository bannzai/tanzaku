import Observation
import TanzakuKit

/// ランチャーの画面の状態。パネルを閉じても次に開く時に使い回し、開くたびに入力と結果を空に戻す。
@Observable
final class LauncherState {
  /// 検索欄に入力した文字列。
  var query = ""
  /// `query` で検索した結果。
  var searchResult = SnippetSearchResult(keywordMatches: [], semanticMatches: [])
  /// `query` の意味検索 (入力のベクトルの推論) が終わっていないか。
  var isSemanticSearchPending = false
  /// ↑↓ で選んでいるスニペットの `launcherSelectableSnippets(searchResult:)` での位置。結果が無ければ `nil`。
  var selectedSnippetIndex: Int?
  /// パネルを開いた回数。開くたびに検索欄へフォーカスを戻すきっかけに使う。
  var presentationCount = 0
  /// ⌘Return で選んだ時の出し方。パネルを開くたびに設定と許可から決め直し、下の案内と ⌘Return の動きの両方がこの値を使う。
  /// 初めに開くまでは画面に出ないため、許可を確かめずに済むコピーにしておく。
  var commandReturnAction = LauncherOutputAction.copy
}
