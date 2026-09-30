import SwiftUI
import TanzakuKit

/// メニューのパネルの幅。スニペットの表示名とキーワードを 1 行に並べて読める幅で、入力欄を隠しすぎないようランチャー (720pt) の半分より狭くする。
private let snippetGroupMenuWidth: CGFloat = 320
/// メニューの 1 行の高さ。macOS の一覧の行 (24〜28pt) に色の帯の余白を足した高さ。
private let snippetGroupMenuRowHeight: CGFloat = 30
/// 上の見出しと下の操作の案内の帯の高さ。
private let snippetGroupMenuBarHeight: CGFloat = 28
/// スクロールせずに並べる行の数の上限。グループのスニペットが多くてもメニューが画面の高さを占めないよう、macOS の補完の候補と同じくらいの行数で止める。
private let snippetGroupMenuMaxVisibleRowCount = 8
/// 一覧の上下の余白。
private let snippetGroupMenuListPadding: CGFloat = 4

/// メニューのパネルの大きさ。パネルを出す位置を決めるため、SwiftUI の配置を待たずに行の数から決める。
func snippetGroupMenuSize(snippetCount: Int) -> CGSize {
  CGSize(
    width: snippetGroupMenuWidth,
    height: snippetGroupMenuBarHeight * 2 + snippetGroupMenuListPadding * 2
      + snippetGroupMenuRowHeight * CGFloat(min(snippetCount, snippetGroupMenuMaxVisibleRowCount))
  )
}

/// スニペットグループのメニューの中身。キー操作 (↑↓・Return・Esc) はキー入力の監視 (`SnippetGroupMenuController`) が受け取る。フォーカスを奪わないパネルに出すため、この画面はキー入力を受けない。
///
/// 色と文字の大きさはランチャー (`LauncherView`) に揃える。
struct SnippetGroupMenuView: View {
  /// メニューの状態。
  let state: SnippetGroupMenuState

  var body: some View {
    VStack(spacing: 0) {
      header
      LauncherColors.line
        .frame(height: 1)
      ScrollViewReader { scrollViewProxy in
        ScrollView {
          VStack(spacing: 0) {
            ForEach(Array(state.snippets.enumerated()), id: \.element.id) { index, snippet in
              row(snippet: snippet, isSelected: index == state.selectedSnippetIndex)
            }
          }
          .padding(.vertical, snippetGroupMenuListPadding)
        }
        .onChange(of: state.selectedSnippetIndex) {
          if state.snippets.indices.contains(state.selectedSnippetIndex) {
            scrollViewProxy.scrollTo(state.snippets[state.selectedSnippetIndex].id)
          }
        }
      }
      LauncherColors.line
        .frame(height: 1)
      footer
    }
    .frame(width: snippetGroupMenuSize(snippetCount: state.snippets.count).width, height: snippetGroupMenuSize(snippetCount: state.snippets.count).height)
    .foregroundStyle(LauncherColors.foreground)
    .background(LauncherColors.panel)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(LauncherColors.panelLine))
    .accessibilityIdentifier("snippet-group-menu")
  }

  /// グループの名前とキーワード。
  private var header: some View {
    HStack(spacing: 8) {
      if let snippetGroup = state.snippetGroup {
        snippetGroupNameText(snippetGroup: snippetGroup)
          .font(.system(size: 12, weight: .semibold))
          .lineLimit(1)
        Spacer(minLength: 0)
        if let keyword = snippetGroup.keyword {
          Text(verbatim: keyword)
            .font(.system(size: 11))
            .foregroundStyle(LauncherColors.tertiaryForeground)
            .lineLimit(1)
        }
      }
    }
    .padding(.horizontal, 12)
    .frame(height: snippetGroupMenuBarHeight - 1)
  }

  /// スニペットの 1 行。色の帯・表示名・キーワードを並べる。
  private func row(snippet: Snippet, isSelected: Bool) -> some View {
    HStack(spacing: 8) {
      RoundedRectangle(cornerRadius: 2)
        .fill(snippet.color.map { snippetBandColor(snippetColor: $0) } ?? .clear)
        .frame(width: 4, height: 16)
      Text(verbatim: snippetDisplayTitle(snippet: snippet))
        .font(.system(size: 13))
        .lineLimit(1)
        .truncationMode(.tail)
      Spacer(minLength: 0)
      if let keyword = snippet.keyword {
        Text(verbatim: keyword)
          .font(.system(size: 11))
          .foregroundStyle(LauncherColors.tertiaryForeground)
          .lineLimit(1)
      }
    }
    .padding(.horizontal, 8)
    .frame(height: snippetGroupMenuRowHeight)
    .background(isSelected ? LauncherColors.selection : .clear, in: RoundedRectangle(cornerRadius: 5))
    .padding(.horizontal, 4)
    .id(snippet.id)
  }

  /// 下の操作の案内。
  private var footer: some View {
    HStack(spacing: 14) {
      Text("↩ Insert")
      Text("↑↓ Select")
      Text("esc Close")
      Spacer(minLength: 0)
    }
    .font(.system(size: 11))
    .foregroundStyle(LauncherColors.secondaryForeground)
    .padding(.horizontal, 12)
    .frame(height: snippetGroupMenuBarHeight - 1)
    .background(LauncherColors.footer)
  }
}
