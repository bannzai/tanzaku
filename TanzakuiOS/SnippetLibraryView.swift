import CoreSpotlight
import SwiftData
import SwiftUI
import TanzakuKit

/// サイドバーの 1 行が表すもの。ライブラリ・フォルダ・タグの絞り込み (`SnippetLibraryFilter`) と、スニペットグループ。
///
/// スニペットグループは Mac の管理ウィンドウでは一覧と編集で扱い、`SnippetLibraryFilter` に無いため、iOS のサイドバーではここで並べる (`documents/DIRECTION.md`「決めたこと」)。
/// グループはモデルではなく識別子で持つ。選択の状態として保持・比較 (`Hashable`) し、消されたグループを参照しないため。
enum SnippetSidebarItem: Hashable {
  /// ライブラリ・フォルダ・タグの絞り込み。
  case library(filter: SnippetLibraryFilter)
  /// スニペットグループ。
  case snippetGroup(snippetGroupID: UUID)
}

/// 本体の画面。iPad (横に広い時) は `NavigationSplitView` の 3 列 (絞り込み・一覧・詳細)、iPhone (横が狭い時) は `NavigationStack` にする (`documents/DIRECTION.md`「デザインの方向」)。
///
/// iPhone は起動した時に「すべてのスニペット」の一覧から始める。スニペットを探してコピーするのが主な使い方で、絞り込みの一覧を毎回通らせないため。
struct SnippetLibraryView: View {
  /// 横に広いか (iPad の全画面・横向き) で列の数を決める。
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  /// 詳細の列に出すスニペットを識別子から引くためのすべてのスニペット。
  @Query private var snippets: [Snippet]
  /// iPad のサイドバーで選んでいる行。
  @State private var selectedSidebarItem: SnippetSidebarItem? = .library(filter: .all)
  /// iPad の詳細の列に出すスニペットの識別子。一覧でタップしたもの。消されたスニペットを参照しないよう識別子で持つ。
  @State private var selectedSnippetID: UUID?
  /// iPhone の画面の積み重ね。最初の画面を「すべてのスニペット」の一覧にするため、それを積んだ状態から始める。
  @State private var compactNavigationPath: [SnippetSidebarItem] = [.library(filter: .all)]
  /// iPhone で Spotlight から開いたスニペットの識別子。詳細の列が無いため sheet で出す。消されたスニペットを参照しないよう識別子で持つ。
  @State private var spotlightSnippetID: UUID?
  #if DEBUG
    /// 開発者メニューで選んだ外観。simtunnel の画面の確認でライト・ダークを撮るため (`AGENTS.md`「画面の確認」)。
    @AppStorage(developerAppearanceUserDefaultsKey) private var developerAppearance = DeveloperAppearance.system
  #endif

  var body: some View {
    Group {
      if horizontalSizeClass == .compact {
        NavigationStack(path: $compactNavigationPath) {
          SnippetSidebarView(selectedSidebarItem: nil)
            .navigationDestination(for: SnippetSidebarItem.self) { sidebarItem in
              SnippetListView(sidebarItem: sidebarItem, selectedSnippetID: nil)
            }
        }
      } else {
        NavigationSplitView {
          SnippetSidebarView(selectedSidebarItem: $selectedSidebarItem)
        } content: {
          SnippetListView(sidebarItem: selectedSidebarItem ?? .library(filter: .all), selectedSnippetID: $selectedSnippetID)
        } detail: {
          if let selectedSnippet = snippets.first(where: { $0.id == selectedSnippetID }) {
            SnippetDetailView(snippet: selectedSnippet)
          } else {
            ContentUnavailableView("Tap a snippet to copy it and see the details here", systemImage: "doc.on.clipboard")
          }
        }
      }
    }
    .task(id: SnippetSpotlightIndexTaskID(snippetIDs: snippets.map(\.id), snippetUpdatedAts: snippets.map(\.updatedAt))) {
      await replaceSnippetSpotlightIndex(snippets: snippets)
    }
    .onContinueUserActivity(CSSearchableItemActionType) { userActivity in
      guard let snippetID = (userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String).flatMap(UUID.init(uuidString:)) else {
        return
      }
      if horizontalSizeClass == .compact {
        spotlightSnippetID = snippetID
      } else {
        selectedSidebarItem = .library(filter: .all)
        selectedSnippetID = snippetID
      }
    }
    .sheet(isPresented: Binding(get: { spotlightSnippetID != nil }, set: { _ in spotlightSnippetID = nil })) {
      NavigationStack {
        Group {
          if let spotlightSnippet = snippets.first(where: { $0.id == spotlightSnippetID }) {
            SnippetDetailView(snippet: spotlightSnippet)
          } else {
            ContentUnavailableView("The snippet was deleted", systemImage: "rectangle.portrait.slash")
          }
        }
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Done") {
              spotlightSnippetID = nil
            }
          }
        }
      }
    }
    #if DEBUG
      .preferredColorScheme(developerAppearance.colorScheme)
    #endif
  }
}

/// Spotlight の索引を入れ直す条件。スニペットの追加・削除 (識別子) と更新 (更新日時) のどれかが変わったら入れ直す。
///
/// 共有シートの拡張が保存したスニペットも、本体の一覧 (`@Query`) に出た時にここで索引に入る。
private struct SnippetSpotlightIndexTaskID: Hashable {
  /// すべてのスニペットの識別子。
  let snippetIDs: [UUID]
  /// すべてのスニペットの更新日時。タイトル・キーワードを変えると変わる。
  let snippetUpdatedAts: [Date]
}

/// サイドバー。ライブラリ (すべて・AI エージェントが追加)・フォルダ・タグ・スニペットグループを並べる (`documents/design/Manager.dc.html` のサイドバー)。
///
/// スニペットグループはここで追加・編集・削除する。
struct SnippetSidebarView: View {
  /// iPad で選んでいる行。iPhone では `nil` で、各行は一覧の画面を積む。
  var selectedSidebarItem: Binding<SnippetSidebarItem?>?

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
  @State private var snippetGroupEditor: SnippetGroupEditorTarget?
  /// 削除の保存の失敗。
  @State private var errorMessage: String?

  var body: some View {
    Group {
      if let selectedSidebarItem {
        List(selection: selectedSidebarItem) {
          sidebarSections
        }
      } else {
        List {
          sidebarSections
        }
      }
    }
    .navigationTitle("Tanzaku")
    .sheet(item: $snippetGroupEditor) { snippetGroupEditor in
      SnippetGroupEditorView(snippetGroup: snippetGroupEditor.snippetGroup)
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
      SnippetSidebarRow(sidebarItem: .library(filter: .all), title: Text("All Snippets"), systemImage: "rectangle.portrait", count: snippets.count)
      SnippetSidebarRow(
        sidebarItem: .library(filter: .addedByAgent),
        title: Text("Added by AI Agents"),
        systemImage: "sparkles",
        count: snippets.filter { snippetMatchesLibraryFilter(snippet: $0, filter: .addedByAgent) }.count
      )
    }
    if !folders.isEmpty {
      Section("Folders") {
        ForEach(folders) { folder in
          SnippetSidebarRow(
            sidebarItem: .library(filter: .folder(folderID: folder.id)),
            title: Text(verbatim: folder.name),
            systemImage: "folder",
            count: folder.snippets?.count ?? 0
          )
        }
      }
    }
    if !tags.isEmpty {
      Section("Tags") {
        ForEach(tags) { tag in
          SnippetSidebarRow(sidebarItem: .library(filter: .tag(tagID: tag.id)), title: Text(verbatim: tag.name), systemImage: "tag", count: tag.snippets?.count ?? 0)
        }
      }
    }
    Section {
      ForEach(snippetGroups) { snippetGroup in
        SnippetSidebarRow(
          sidebarItem: .snippetGroup(snippetGroupID: snippetGroup.id),
          title: Text(verbatim: snippetGroup.name),
          systemImage: "list.bullet.rectangle",
          count: sortedSnippetGroupItems(snippetGroup: snippetGroup).compactMap(\.snippet).count
        )
        .swipeActions {
          Button("Delete", role: .destructive) {
            deleteSnippetGroup(snippetGroup: snippetGroup)
          }
          Button("Edit") {
            snippetGroupEditor = SnippetGroupEditorTarget(snippetGroup: snippetGroup)
          }
        }
        .contextMenu {
          Button("Edit", systemImage: "pencil") {
            snippetGroupEditor = SnippetGroupEditorTarget(snippetGroup: snippetGroup)
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
          snippetGroupEditor = SnippetGroupEditorTarget(snippetGroup: nil)
        }
        .labelStyle(.iconOnly)
      }
    }
  }

  /// スニペットグループを消して保存する。グループの項目はリレーションの削除ルールで消え、スニペットは残る。選んでいたら「すべてのスニペット」に戻す。
  private func deleteSnippetGroup(snippetGroup: SnippetGroup) {
    if selectedSidebarItem?.wrappedValue == .snippetGroup(snippetGroupID: snippetGroup.id) {
      selectedSidebarItem?.wrappedValue = .library(filter: .all)
    }
    modelContext.delete(snippetGroup)
    errorMessage = saveSnippetChanges(modelContext: modelContext)
  }
}

/// スニペットグループの編集画面 (sheet) で編集するもの。`nil` は新規。`sheet(item:)` に渡すため `Identifiable` にする。
struct SnippetGroupEditorTarget: Identifiable {
  /// 編集するスニペットグループ。`nil` は新規。
  let snippetGroup: SnippetGroup?
  /// sheet を出すたびに別のものとして扱う識別子。新規は同じグループが無いため、毎回作る。
  let id = UUID()
}

/// サイドバーの 1 行。iPad ではリストの選択、iPhone では一覧の画面を積むリンクになる。
private struct SnippetSidebarRow: View {
  /// 行が表すもの。
  var sidebarItem: SnippetSidebarItem
  /// 行の名前。フォルダ・タグ・グループの名前はユーザーが付けたもので翻訳しないため、呼び出し側で `Text(verbatim:)` にする。
  var title: Text
  /// 行のアイコン。
  var systemImage: String
  /// 当てはまるスニペットの件数。
  var count: Int

  var body: some View {
    NavigationLink(value: sidebarItem) {
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
