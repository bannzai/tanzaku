import Foundation
import TanzakuKit

/// ランチャーの本体の欄に何を出すか。
enum LauncherContentState: Equatable {
  /// 何も入力しておらず、使ったことのあるスニペットがある。最近使ったスニペットの欄を出す。
  case recentSnippets
  /// 何も入力しておらず、使ったことのあるスニペットが無い。結果なしの案内と同じ形で新規作成 (⌘N) の案内を出す。
  case noRecentSnippets
  /// 結果がある。キーワードが一致した欄と意味が近い欄を出す (`documents/design/Main.dc.html`)。
  case results
  /// 文字列の一致は無く、意味検索の結果を待っている。結果なしの案内も新規作成 (⌘N) も出さない。意味検索で見つかる入力で、結果なしの案内を一瞬出したり新規作成へ進めたりしないため。
  case searching
  /// 入力したが結果が無い。入力した言葉で新規作成する案内を出す (`documents/design/LauncherEmpty.dc.html`)。
  case empty
}

/// 入力・最近使ったスニペット・検索の結果から、本体の欄に出すものを決める。空白だけの入力は検索しないため (`searchSnippets(query:modelContext:embedder:)`)、何も入力していないのと同じに扱う。
func launcherContentState(query: String, recentSnippets: [Snippet], searchResult: SnippetSearchResult, isSemanticSearchPending: Bool) -> LauncherContentState {
  if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    return recentSnippets.isEmpty ? .noRecentSnippets : .recentSnippets
  }
  if !launcherSelectableSnippets(recentSnippets: [], searchResult: searchResult).isEmpty {
    return .results
  }
  return isSemanticSearchPending ? .searching : .empty
}

/// ↑↓ で選べる順のスニペット。画面の上から、最近使った欄、キーワードが一致した欄、意味が近い欄の順に並ぶため、この順につなげる。
///
/// 最近使ったスニペットは検索語が空の時だけ持ち、検索の結果は検索語がある時だけ持つ (`LauncherState`) ため、並ぶのはどちらか一方になる。
func launcherSelectableSnippets(recentSnippets: [Snippet], searchResult: SnippetSearchResult) -> [Snippet] {
  recentSnippets + searchResult.keywordMatches.map(\.snippet) + searchResult.semanticMatches
}

/// 選んでいる位置のスニペット。位置が無い・結果の範囲の外 (結果が入れ替わった直後) なら `nil`。
func launcherSelectedSnippet(recentSnippets: [Snippet], searchResult: SnippetSearchResult, selectedSnippetIndex: Int?) -> Snippet? {
  let selectableSnippets = launcherSelectableSnippets(recentSnippets: recentSnippets, searchResult: searchResult)
  guard let selectedSnippetIndex, selectableSnippets.indices.contains(selectedSnippetIndex) else {
    return nil
  }
  return selectableSnippets[selectedSnippetIndex]
}

/// 結果を入れ替えた (入力が変わった・意味検索の結果が届いた・ベクトルを作り直した) 後の選択の位置。
///
/// 選んでいたスニペットが新しい結果にもあれば、その位置を選び続ける。ユーザーが操作していない時に選択が別のスニペットへ移ると、直後の Return で意図しない本文をコピーするため。無ければ先頭を選ぶ。
func launcherSelectionIndexAfterResultUpdate(recentSnippets: [Snippet], searchResult: SnippetSearchResult, selectedSnippetID: UUID?) -> Int? {
  let selectableSnippets = launcherSelectableSnippets(recentSnippets: recentSnippets, searchResult: searchResult)
  if let selectedSnippetID, let index = selectableSnippets.firstIndex(where: { $0.id == selectedSnippetID }) {
    return index
  }
  return launcherMovedSelectionIndex(currentIndex: nil, offset: 0, count: selectableSnippets.count)
}

/// ↑↓ で選択を動かした後の位置。端で止め、先頭から末尾へ回り込ませない (macOS の一覧の ↑↓ と同じ)。結果が無ければ `nil`。
func launcherMovedSelectionIndex(currentIndex: Int?, offset: Int, count: Int) -> Int? {
  guard count > 0 else {
    return nil
  }
  guard let currentIndex else {
    return 0
  }
  return min(max(currentIndex + offset, 0), count - 1)
}

/// キーワードの欄の表示で、入力と一致した先頭 (太字で出す部分) と残り。
struct LauncherKeywordHighlight: Equatable {
  /// 入力と一致したキーワードの先頭。
  var matchedPrefix: String
  /// キーワードの残り。
  var remainder: String
}

/// キーワードのうち入力と一致した先頭を分ける。キーワードの完全一致・前方一致の時だけ先頭を太字にし、タイトル・本文で一致した時はキーワード全体を残りとして返す。
///
/// 検索は大文字と小文字・全角と半角・ひらがなとカタカナを揃えて比べる (`searchSnippets(query:modelContext:embedder:)`)。キーワードに使う英数字・かなは揃えても文字数が変わらないため、入力の文字数でキーワードを分ける。太字の範囲は表示だけに使うため、文字数が変わる文字 (ß など) でずれても実害は無い。
func launcherKeywordHighlight(keyword: String, query: String, matchKind: SnippetKeywordMatchKind?) -> LauncherKeywordHighlight {
  switch matchKind {
  case .keywordExact, .keywordPrefix:
    let matchedCount = min(query.trimmingCharacters(in: .whitespacesAndNewlines).count, keyword.count)
    return LauncherKeywordHighlight(matchedPrefix: String(keyword.prefix(matchedCount)), remainder: String(keyword.dropFirst(matchedCount)))
  case .titleOrBody, nil:
    return LauncherKeywordHighlight(matchedPrefix: "", remainder: keyword)
  }
}
