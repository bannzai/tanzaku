import SwiftData
import SwiftUI
import TanzakuKit

/// 本体の画面。iPad (横に広い時) は `NavigationSplitView` の 3 列 (絞り込み・一覧・詳細)、iPhone (横が狭い時) は `NavigationStack` にする (`documents/DIRECTION.md`「デザインの方向」)。
///
/// iPhone は起動した時に「すべてのスニペット」の一覧から始める。スニペットを探してコピーするのが主な使い方で、絞り込みの一覧を毎回通らせないため。
struct SnippetLibraryView: View {
  /// 横に広いか (iPad の全画面・横向き) で列の数を決める。
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  /// iPad のサイドバーで選んでいる絞り込み。
  @State private var selectedFilter: SnippetLibraryFilter? = .allSnippets
  /// iPad の詳細の列に出すスニペット。一覧でタップしたもの。
  @State private var selectedSnippet: Snippet?
  /// iPhone の画面の積み重ね。最初の画面を「すべてのスニペット」の一覧にするため、それを積んだ状態から始める。
  @State private var compactNavigationPath: [SnippetLibraryFilter] = [.allSnippets]
  #if DEBUG
    /// 開発者メニューで選んだ外観。simtunnel の画面の確認でライト・ダークを撮るため (`AGENTS.md`「画面の確認」)。
    @AppStorage(developerAppearanceUserDefaultsKey) private var developerAppearance = DeveloperAppearance.system
  #endif

  var body: some View {
    Group {
      if horizontalSizeClass == .compact {
        NavigationStack(path: $compactNavigationPath) {
          SnippetSidebarView(selectedFilter: nil)
            .navigationDestination(for: SnippetLibraryFilter.self) { filter in
              SnippetListView(filter: filter, selectedSnippet: nil)
            }
        }
      } else {
        NavigationSplitView {
          SnippetSidebarView(selectedFilter: $selectedFilter)
        } content: {
          SnippetListView(filter: selectedFilter ?? .allSnippets, selectedSnippet: $selectedSnippet)
        } detail: {
          if let selectedSnippet {
            SnippetDetailView(snippet: selectedSnippet) {
              self.selectedSnippet = nil
            }
          } else {
            ContentUnavailableView("Tap a snippet to copy it and see the details here", systemImage: "doc.on.clipboard")
          }
        }
      }
    }
    #if DEBUG
      .preferredColorScheme(developerAppearance.colorScheme)
    #endif
  }
}

/// 絞り込みの一覧。ライブラリ (すべて・AI エージェントが追加)・フォルダ・タグ・スニペットグループを並べる (`documents/design/Manager.dc.html` のサイドバー)。
///
/// スニペットグループはここで追加・編集・削除する。
struct SnippetSidebarView: View {
  /// iPad で選んでいる絞り込み。iPhone では `nil` で、各行は一覧の画面を積む。
  var selectedFilter: Binding<SnippetLibraryFilter?>?

  /// 件数を数えるすべてのスニペット。
  @Query private var snippets: [Snippet]
  /// フォルダ。名前の順。
  @Query(sort: \Folder.name) private var folders: [Folder]
  /// タグ。名前の順。
  @Query(sort: \Tag.name) private var tags: [Tag]
  /// スニペットグループ。名前の順。
  @Query(sort: \SnippetGroup.name) private var snippetGroups: [SnippetGroup]
  /// 削除に使う。
  @Environment(\.modelContext) private var modelContext
  /// 編集画面を出しているスニペットグループ。
  @State private var editingSnippetGroup: SnippetGroup?
  /// 編集画面が追加か。
  @State private var isEditingNewSnippetGroup = false
  /// 保存・削除の失敗。
  @State private var errorMessage: String?

  var body: some View {
    Group {
      if let selectedFilter {
        List(selection: selectedFilter) {
          sidebarSections
        }
      } else {
        List {
          sidebarSections
        }
      }
    }
    .navigationTitle("Tanzaku")
    .sheet(
      item: $editingSnippetGroup,
      onDismiss: {
        // 取り消した編集を捨てる。保存した後なら捨てるものは無い。
        modelContext.rollback()
      }
    ) { snippetGroup in
      SnippetGroupEditorView(snippetGroup: snippetGroup, isNewSnippetGroup: isEditingNewSnippetGroup)
    }
    .alert("Could not save", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
      Button("OK") {}
    } message: {
      Text(verbatim: errorMessage ?? "")
    }
  }

  /// サイドバーの見出しごとの行。
  @ViewBuilder private var sidebarSections: some View {
    Section("Library") {
      SnippetSidebarRow(filter: .allSnippets, title: Text("All Snippets"), systemImage: "rectangle.portrait", count: snippets.count)
      SnippetSidebarRow(
        filter: .addedByAgent,
        title: Text("Added by AI Agents"),
        systemImage: "sparkles",
        count: filteredLibrarySnippets(snippets: snippets, filter: .addedByAgent).count
      )
    }
    if !folders.isEmpty {
      Section("Folders") {
        ForEach(folders) { folder in
          SnippetSidebarRow(filter: .folder(folder), title: Text(verbatim: folder.name), systemImage: "folder", count: folder.snippets?.count ?? 0)
        }
      }
    }
    if !tags.isEmpty {
      Section("Tags") {
        ForEach(tags) { tag in
          SnippetSidebarRow(filter: .tag(tag), title: Text(verbatim: tag.name), systemImage: "tag", count: tag.snippets?.count ?? 0)
        }
      }
    }
    Section {
      ForEach(snippetGroups) { snippetGroup in
        SnippetSidebarRow(
          filter: .snippetGroup(snippetGroup),
          title: Text(verbatim: snippetGroup.name),
          systemImage: "list.bullet.rectangle",
          count: snippetGroupSnippets(snippetGroup: snippetGroup).count
        )
        .swipeActions {
          Button("Delete", role: .destructive) {
            deleteSnippetGroup(snippetGroup: snippetGroup)
          }
          Button("Edit") {
            isEditingNewSnippetGroup = false
            editingSnippetGroup = snippetGroup
          }
        }
        .contextMenu {
          Button("Edit", systemImage: "pencil") {
            isEditingNewSnippetGroup = false
            editingSnippetGroup = snippetGroup
          }
          Button("Delete", systemImage: "trash", role: .destructive) {
            deleteSnippetGroup(snippetGroup: snippetGroup)
          }
        }
      }
    } header: {
      HStack {
        Text("Snippet Groups")
        Spacer()
        Button("New Snippet Group", systemImage: "plus") {
          let snippetGroup = SnippetGroup(name: "")
          modelContext.insert(snippetGroup)
          isEditingNewSnippetGroup = true
          editingSnippetGroup = snippetGroup
        }
        .labelStyle(.iconOnly)
      }
    }
  }

  /// スニペットグループを消して保存する。グループの項目はリレーションの削除ルールで消え、スニペットは残る。
  private func deleteSnippetGroup(snippetGroup: SnippetGroup) {
    if case .snippetGroup(let selectedSnippetGroup) = selectedFilter?.wrappedValue, selectedSnippetGroup.id == snippetGroup.id {
      selectedFilter?.wrappedValue = .allSnippets
    }
    modelContext.delete(snippetGroup)
    do {
      try modelContext.save()
    } catch {
      modelContext.rollback()
      errorMessage = String(describing: error)
    }
  }
}

/// サイドバーの 1 行。iPad ではリストの選択、iPhone では一覧の画面を積むリンクになる。
private struct SnippetSidebarRow: View {
  /// 行の絞り込み。
  var filter: SnippetLibraryFilter
  /// 行の名前。フォルダ・タグ・グループの名前はユーザーが付けたもので翻訳しないため、呼び出し側で `Text(verbatim:)` にする。
  var title: Text
  /// 行のアイコン。
  var systemImage: String
  /// 当てはまるスニペットの件数。
  var count: Int

  var body: some View {
    NavigationLink(value: filter) {
      LabeledContent {
        Text(count, format: .number)
      } label: {
        Label {
          title
        } icon: {
          Image(systemName: systemImage)
        }
      }
    }
  }
}
