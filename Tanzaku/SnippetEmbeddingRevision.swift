import Observation

/// 意味検索のベクトルを作り直した回数。管理ウィンドウの検索がこれを見て、埋め込みモデルの用意が済んだ時とベクトルを作り直した時に今の入力で検索し直す。
///
/// 埋め込みモデルとベクトルはランチャー (`LauncherPanelController`) が持ち、ランチャーは SwiftUI から変化を見られないため、変化だけをこれで伝える。
@Observable
final class SnippetEmbeddingRevision {
  /// ベクトルを作り直すたびに 1 増える。値そのものに意味は無く、変わったことだけを使う。
  var value = 0
}
