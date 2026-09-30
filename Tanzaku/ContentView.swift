import SwiftUI

/// 管理ウィンドウの中身。雛形の段階の仮の画面で、管理ウィンドウの issue (#11) が `documents/design/Manager.dc.html` の画面に置き換える。
///
/// ランチャーから新規作成に進んだ時は、仮の画面のまま下書きのタイトルを出す。#11 はこの下書き (`NewSnippetDraft`) を読んで編集を開く。
struct ContentView: View {
  /// ランチャーから新規作成に進んだ時の下書き。
  @Environment(NewSnippetDraft.self) private var newSnippetDraft

  var body: some View {
    VStack(spacing: 12) {
      Text("Tanzaku")
        .font(.largeTitle)
      if let draftTitle = newSnippetDraft.title {
        Text("New snippet: \(draftTitle)")
          .accessibilityIdentifier("newSnippetDraftTitle")
      }
    }
    .frame(minWidth: 480, minHeight: 320)
  }
}

#Preview {
  ContentView()
    .environment(NewSnippetDraft())
}
