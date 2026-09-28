import SwiftData
import SwiftUI
import TanzakuKit

/// 管理ウィンドウのサイドバーで選んでいる項目。
enum ManagerSidebarSelection: Hashable {
  /// スニペットの一覧を絞り込んで出す。
  case snippets(filter: SnippetLibraryFilter)
  /// スニペットグループの一覧を出す。
  case snippetGroups
}

/// 管理ウィンドウの一覧で選んでいる項目。編集画面に出すものを決める。
enum ManagerDetailSelection: Hashable {
  /// 既存のスニペット。
  case snippet(snippetID: UUID)
  /// 新規のスニペット。保存するまでストアに入れないため、押すたびに編集画面を作り直すよう下書きごとの識別子を持つ。
  case newSnippet(draftID: UUID)
  /// 既存のスニペットグループ。
  case snippetGroup(snippetGroupID: UUID)
  /// 新規のスニペットグループ。識別子を持つ理由は `newSnippet` と同じ。
  case newSnippetGroup(draftID: UUID)
}

/// 管理ウィンドウ。サイドバー・一覧・編集の 3 列 (`documents/design/Manager.dc.html`)。
struct ManagerView: View {
  @Environment(\.modelContext) private var modelContext
  /// 意味検索に使う埋め込みモデル。起動後に資産を用意できるまでは `nil` で、その間は意味検索なしで検索する。
  @State private var embedder: SnippetTextEmbedder?
  /// サイドバーで選んでいる項目。起動時はデザインと同じく「すべてのスニペット」を選ぶ。
  @State private var sidebarSelection: ManagerSidebarSelection? = .snippets(filter: .all)
  /// 一覧で選んでいる項目。
  @State private var detailSelection: ManagerDetailSelection?
  /// 検索欄に入力した文字列。
  @State private var searchText = ""

  var body: some View {
    NavigationSplitView {
      ManagerSidebar(selection: $sidebarSelection)
        .navigationSplitViewColumnWidth(min: 200, ideal: 230)
    } content: {
      Group {
        switch sidebarSelection ?? .snippets(filter: .all) {
        case .snippetGroups:
          SnippetGroupListView(searchText: searchText, selection: $detailSelection)
        case .snippets(let filter):
          SnippetListView(filter: filter, searchText: searchText, embedder: embedder, selection: $detailSelection)
        }
      }
      .navigationSplitViewColumnWidth(min: 280, ideal: 340)
      .searchable(text: $searchText, placement: .toolbar, prompt: Text("Search by keyword or meaning"))
      .toolbar {
        ToolbarItem {
          Button {
            detailSelection = sidebarSelection == .snippetGroups ? .newSnippetGroup(draftID: UUID()) : .newSnippet(draftID: UUID())
          } label: {
            if sidebarSelection == .snippetGroups {
              Label("New Snippet Group", systemImage: "plus")
            } else {
              Label("New Snippet", systemImage: "plus")
            }
          }
          .keyboardShortcut("n")
          .accessibilityIdentifier("new-item-button")
        }
      }
    } detail: {
      ManagerDetailView(selection: $detailSelection, embedder: embedder)
    }
    .onChange(of: sidebarSelection) {
      detailSelection = nil
    }
    .task {
      embedder = await prepareSnippetTextEmbedder(modelContext: modelContext)
    }
  }
}

/// 一覧で選んだ項目の編集画面。
private struct ManagerDetailView: View {
  /// 一覧で選んでいる項目。
  @Binding var selection: ManagerDetailSelection?
  /// 保存・削除の後に意味検索のベクトルを作り直す埋め込みモデル。
  let embedder: SnippetTextEmbedder?
  /// 選んだ識別子のスニペットを探すためのすべてのスニペット。
  @Query private var snippets: [Snippet]
  /// 選んだ識別子のスニペットグループを探すためのすべてのスニペットグループ。
  @Query private var snippetGroups: [SnippetGroup]

  var body: some View {
    switch selection {
    case .snippet(let snippetID):
      if let snippet = snippets.first(where: { $0.id == snippetID }) {
        SnippetEditorView(snippet: snippet, embedder: embedder, selection: $selection)
          .id(selection)
      } else {
        noSelectionView
      }
    case .newSnippet:
      SnippetEditorView(snippet: nil, embedder: embedder, selection: $selection)
        .id(selection)
    case .snippetGroup(let snippetGroupID):
      if let snippetGroup = snippetGroups.first(where: { $0.id == snippetGroupID }) {
        SnippetGroupEditorView(snippetGroup: snippetGroup, selection: $selection)
          .id(selection)
      } else {
        noSelectionView
      }
    case .newSnippetGroup:
      SnippetGroupEditorView(snippetGroup: nil, selection: $selection)
        .id(selection)
    case nil:
      noSelectionView
    }
  }

  /// 何も選んでいない時の表示。
  private var noSelectionView: some View {
    Text("Select an item")
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
