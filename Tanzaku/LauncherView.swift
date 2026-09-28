import SwiftUI
import TanzakuKit

/// ランチャーのパネルの中身。配置と寸法は `documents/design/Main.dc.html` (結果あり・結果なし) に合わせる。キー操作 (↑↓・Return・⌘Return・⌘N・Esc) は `LauncherPanelController` が受け取る。
struct LauncherView: View {
  /// 画面の状態。
  @Bindable var state: LauncherState
  /// 入力が変わった時に呼ぶ。検索は `LauncherPanelController` が行う。
  var onQueryChange: () -> Void
  /// 結果の行をダブルクリックした時に呼ぶ (Return と同じくコピーして閉じる)。
  var onCopySelectedSnippet: () -> Void
  /// 結果なしの画面の新規作成のボタンを押した時に呼ぶ (⌘N と同じ)。
  var onCreateSnippet: () -> Void

  /// 検索欄にフォーカスがあるか。
  @FocusState private var isQueryFieldFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      queryField
      LauncherLine()
      switch launcherContentState(query: state.query, searchResult: state.searchResult) {
      case .idle:
        Spacer(minLength: 0)
      case .results:
        results
      case .empty:
        emptyResult
      }
      LauncherLine()
      footer
    }
    .frame(width: 720, height: 480)
    .foregroundStyle(LauncherColors.foreground)
    .background(LauncherColors.panel)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LauncherColors.panelLine))
    .onAppear {
      isQueryFieldFocused = true
    }
    .onChange(of: state.presentationCount) {
      isQueryFieldFocused = true
    }
  }

  /// 上の検索欄と件数。
  private var queryField: some View {
    HStack(spacing: 12) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 17))
        .foregroundStyle(LauncherColors.secondaryForeground)
      TextField("Search snippets", text: $state.query)
        .textFieldStyle(.plain)
        .font(.system(size: 20))
        .focused($isQueryFieldFocused)
        .accessibilityIdentifier("launcherQueryField")
        .onChange(of: state.query) {
          onQueryChange()
        }
      if launcherContentState(query: state.query, searchResult: state.searchResult) != .idle {
        Text("\(launcherSelectableSnippets(searchResult: state.searchResult).count) results")
          .font(.system(size: 12))
          .foregroundStyle(LauncherColors.tertiaryForeground)
      }
    }
    .padding(.horizontal, 18)
    .frame(height: 56)
  }

  /// 結果の一覧と、選んでいるスニペットのプレビュー。
  private var results: some View {
    HStack(spacing: 0) {
      ScrollViewReader { scrollViewProxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 2) {
            LauncherSectionHeader(title: "Keyword matches", topPadding: 6)
            ForEach(Array(state.searchResult.keywordMatches.enumerated()), id: \.element.snippet.id) { index, keywordMatch in
              LauncherResultRow(
                snippet: keywordMatch.snippet,
                isSelected: state.selectedSnippetIndex == index,
                subtitle: snippetBodyFirstLine(body: keywordMatch.snippet.body),
                isSubtitleMonospaced: true
              ) {
                keywordMatch.snippet.keyword.map { keyword in
                  LauncherKeywordChip(highlight: launcherKeywordHighlight(keyword: keyword, query: state.query, matchKind: keywordMatch.kind))
                }
              }
              .onTapGesture(count: 2) {
                state.selectedSnippetIndex = index
                onCopySelectedSnippet()
              }
              .onTapGesture {
                state.selectedSnippetIndex = index
              }
            }
            LauncherSectionHeader(title: "Similar meaning", topPadding: 12)
            ForEach(Array(state.searchResult.semanticMatches.enumerated()), id: \.element.id) { offset, snippet in
              LauncherResultRow(
                snippet: snippet,
                isSelected: state.selectedSnippetIndex == state.searchResult.keywordMatches.count + offset,
                subtitle: snippetBodyFirstLine(body: snippet.body),
                isSubtitleMonospaced: false
              ) {
                snippet.keyword.map { keyword in
                  HStack(spacing: 4) {
                    Image(systemName: "water.waves")
                      .font(.system(size: 11))
                    Text(verbatim: keyword)
                  }
                  .font(.system(size: 12))
                  .foregroundStyle(LauncherColors.tertiaryForeground)
                }
              }
              .onTapGesture(count: 2) {
                state.selectedSnippetIndex = state.searchResult.keywordMatches.count + offset
                onCopySelectedSnippet()
              }
              .onTapGesture {
                state.selectedSnippetIndex = state.searchResult.keywordMatches.count + offset
              }
            }
          }
          .padding(8)
        }
        .onChange(of: state.selectedSnippetIndex) {
          if let selectedSnippet {
            scrollViewProxy.scrollTo(selectedSnippet.id)
          }
        }
      }
      .frame(width: 330)
      LauncherLine(axis: .vertical)
      if let selectedSnippet {
        LauncherSnippetPreview(snippet: selectedSnippet)
      } else {
        Spacer(minLength: 0)
      }
    }
  }

  /// 結果なしの案内と新規作成のボタン。
  private var emptyResult: some View {
    VStack(spacing: 14) {
      LauncherTanzakuIcon()
        .stroke(LauncherColors.tertiaryForeground, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        .frame(width: 36, height: 36)
      Text("No snippets close to “\(trimmedQuery)”")
        .font(.system(size: 15, weight: .semibold))
      Text("Searched by the meaning of keywords, titles, and bodies.\nIf you use it often, you can make a snippet from here.")
        .font(.system(size: 13))
        .foregroundStyle(LauncherColors.secondaryForeground)
        .lineSpacing(4)
      Button(action: onCreateSnippet) {
        HStack(spacing: 10) {
          Image(systemName: "plus")
            .font(.system(size: 12, weight: .semibold))
          Text("Create a new snippet “\(trimmedQuery)”")
          Text(verbatim: "⌘N")
            .font(.system(size: 12))
            .opacity(0.85)
        }
        .font(.system(size: 13))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(LauncherColors.accent, in: RoundedRectangle(cornerRadius: 6))
      }
      .buttonStyle(.plain)
      .padding(.top, 6)
      .accessibilityIdentifier("launcherCreateSnippetButton")
      Text("Opens the editor in the manager window with your words as the title")
        .font(.system(size: 12))
        .foregroundStyle(LauncherColors.tertiaryForeground)
    }
    .multilineTextAlignment(.center)
    .padding(.horizontal, 64)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  /// 下の操作の案内。結果なしの時は新規作成と閉じるだけを出す。
  private var footer: some View {
    HStack(spacing: 18) {
      if launcherContentState(query: state.query, searchResult: state.searchResult) == .empty {
        LauncherKeyHint(key: "⌘N", label: "New")
        LauncherKeyHint(key: "esc", label: "Close")
      } else {
        LauncherKeyHint(key: "↩", label: "Copy")
        LauncherKeyHint(key: "⌘↩", label: "Paste to the front app")
        LauncherKeyHint(key: "↑↓", label: "Select")
        LauncherKeyHint(key: "esc", label: "Close")
      }
      Spacer(minLength: 0)
    }
    .font(.system(size: 12))
    .foregroundStyle(LauncherColors.secondaryForeground)
    .padding(.horizontal, 18)
    .frame(height: 40)
    .background(LauncherColors.footer)
  }

  /// 選んでいるスニペット。
  private var selectedSnippet: Snippet? {
    launcherSelectedSnippet(searchResult: state.searchResult, selectedSnippetIndex: state.selectedSnippetIndex)
  }

  /// 前後の空白を除いた入力。結果なしの文言に使う。
  private var trimmedQuery: String {
    state.query.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

/// ランチャーの区切り線 (幅 1px)。
private struct LauncherLine: View {
  /// 線の向き。
  var axis: Axis = .horizontal

  var body: some View {
    LauncherColors.line
      .frame(width: axis == .vertical ? 1 : nil, height: axis == .horizontal ? 1 : nil)
  }
}

/// 結果の欄の見出し。
private struct LauncherSectionHeader: View {
  /// 見出しの文言。
  var title: LocalizedStringKey
  /// 上の余白。最初の欄と 2 つ目の欄で違う (デザインの 6px と 12px)。
  var topPadding: CGFloat

  var body: some View {
    Text(title)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(LauncherColors.tertiaryForeground)
      .padding(EdgeInsets(top: topPadding, leading: 10, bottom: 4, trailing: 10))
  }
}

/// 結果の 1 行。色の帯・名前・本文の 1 行目と、右端の付属の表示 (キーワードなど) を並べる。
private struct LauncherResultRow<Accessory: View>: View {
  /// 行のスニペット。
  var snippet: Snippet
  /// 選んでいる行か。
  var isSelected: Bool
  /// 名前の下の 1 行。
  var subtitle: String
  /// `subtitle` を等幅で出すか。本文の書き出しは等幅で出す (`documents/DIRECTION.md`「決めたこと」)。
  var isSubtitleMonospaced: Bool
  /// 右端の表示。
  @ViewBuilder var accessory: () -> Accessory

  var body: some View {
    HStack(spacing: 10) {
      LauncherColorBand(snippet: snippet, height: 34)
      VStack(alignment: .leading, spacing: 3) {
        Text(verbatim: snippetDisplayTitle(snippet: snippet))
          .font(.system(size: 13, weight: .semibold))
        Text(verbatim: subtitle)
          .font(isSubtitleMonospaced ? .system(size: 12, design: .monospaced) : .system(size: 12))
          .foregroundStyle(LauncherColors.secondaryForeground)
      }
      .lineLimit(1)
      .truncationMode(.tail)
      Spacer(minLength: 0)
      accessory()
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(isSelected ? LauncherColors.selection : .clear, in: RoundedRectangle(cornerRadius: 7))
    .contentShape(Rectangle())
    .id(snippet.id)
  }
}

/// スニペットの色の帯 (幅 4px)。色が無いスニペットは帯を出さず、幅だけ空けて名前の位置を揃える (`documents/DIRECTION.md`「決めたこと」)。
private struct LauncherColorBand: View {
  /// 帯のスニペット。
  var snippet: Snippet
  /// 帯の高さ。
  var height: CGFloat

  var body: some View {
    RoundedRectangle(cornerRadius: 2)
      .fill(snippet.colorRawValue.flatMap(SnippetColor.init(rawValue:)).map { snippetBandColor(snippetColor: $0) } ?? .clear)
      .frame(width: 4, height: height)
  }
}

/// キーワードの枠。入力と一致した先頭を太字にする。
private struct LauncherKeywordChip: View {
  /// 太字にする部分と残り。
  var highlight: LauncherKeywordHighlight

  var body: some View {
    Text(highlightedKeyword)
      .font(.system(size: 12))
      .foregroundStyle(LauncherColors.secondaryForeground)
      .padding(.horizontal, 6)
      .padding(.vertical, 1)
      .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(LauncherColors.strongLine))
  }

  /// 一致した先頭だけを太字・強調の色にしたキーワード。
  private var highlightedKeyword: AttributedString {
    var matchedPrefix = AttributedString(highlight.matchedPrefix)
    matchedPrefix.font = .system(size: 12, weight: .bold)
    matchedPrefix.foregroundColor = LauncherColors.accentText
    return matchedPrefix + AttributedString(highlight.remainder)
  }
}

/// 選んでいるスニペットのプレビュー。名前・キーワード・タグ・フォルダと本文を出す。
private struct LauncherSnippetPreview: View {
  /// プレビューするスニペット。
  var snippet: Snippet

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        LauncherColorBand(snippet: snippet, height: 20)
        Text(verbatim: snippetDisplayTitle(snippet: snippet))
          .font(.system(size: 15, weight: .semibold))
          .lineLimit(1)
      }
      HStack(spacing: 14) {
        if let keyword = snippet.keyword, !keyword.isEmpty {
          Text("Keyword \(keyword)")
        }
        if let tags = snippet.tags, !tags.isEmpty {
          Text("Tags \(tags.map(\.name).sorted().joined(separator: ", "))")
        }
        if let folder = snippet.folder {
          Text("Folder \(folder.name)")
        }
      }
      .font(.system(size: 12))
      .foregroundStyle(LauncherColors.secondaryForeground)
      .lineLimit(1)
      ScrollView {
        Text(verbatim: snippet.body)
          .font(.system(size: 12, design: .monospaced))
          .lineSpacing(7)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 14)
          .padding(.vertical, 12)
      }
      .frame(maxHeight: .infinity)
      .background(LauncherColors.code, in: RoundedRectangle(cornerRadius: 8))
      .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(LauncherColors.line))
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

/// 下の案内の 1 つ。キーを枠で囲み、その後に操作の名前を置く。
private struct LauncherKeyHint: View {
  /// キーの表記。記号とキー名で、翻訳しない。
  var key: String
  /// 操作の名前。
  var label: LocalizedStringKey

  var body: some View {
    HStack(spacing: 6) {
      Text(verbatim: key)
        .font(.system(size: 11))
        .foregroundStyle(LauncherColors.foreground)
        .padding(.horizontal, 5)
        .frame(minWidth: 20, minHeight: 20)
        .background(LauncherColors.panel, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(LauncherColors.strongLine))
      Text(label)
    }
  }
}

/// 結果なしの画面の短冊のアイコン (`documents/design/Main.dc.html` の 36px の SVG と同じ形)。
private struct LauncherTanzakuIcon: Shape {
  func path(in rect: CGRect) -> Path {
    // SVG の viewBox (36 x 36) の座標を rect の大きさに合わせる。
    let scale = min(rect.width, rect.height) / 36
    var path = Path()
    path.addRoundedRect(in: CGRect(x: 12 * scale, y: 4 * scale, width: 12 * scale, height: 28 * scale), cornerSize: CGSize(width: 2 * scale, height: 2 * scale))
    path.move(to: CGPoint(x: 16 * scale, y: 11 * scale))
    path.addLine(to: CGPoint(x: 20 * scale, y: 11 * scale))
    path.move(to: CGPoint(x: 16 * scale, y: 16 * scale))
    path.addLine(to: CGPoint(x: 20 * scale, y: 16 * scale))
    return path
  }
}
