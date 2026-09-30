import Observation

/// ランチャーの結果なしの画面から新規作成 (⌘N) に進んだ時の下書き。管理ウィンドウ (#11) の編集がこれを読んで、入力した言葉をタイトルにした新規作成を始める。
@Observable
final class NewSnippetDraft {
  /// 下書きのタイトル (ランチャーに入力した言葉)。新規作成に進んでいなければ `nil`。
  var title: String?
}
