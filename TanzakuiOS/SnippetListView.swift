import SwiftData
import SwiftUI
import TanzakuKit

/// スニペットの一覧。タップで本文をコピーし、検索・追加・編集・削除・共有をここから行う。
///
/// iOS ではほかのアプリの入力欄へ貼るのが主な使い方のため、行のタップをコピーにする。編集と削除は行のスワイプと長押しのメニューに置く。
/// iPad では、タップした行を詳細の列にも出す。
struct SnippetListView: View {
  /// サイドバーで選んだ行。
  var sidebarItem: SnippetSidebarItem
  /// iPad の詳細の列に出すスニペットの識別子。iPhone では `nil`。
  var selectedSnippetID: Binding<UUID?>?

  /// すべてのスニペット。更新日時の新しい順 (`documents/design/Manager.dc.html` の一覧)。スニペットの追加・更新・削除で一覧を描き直すため `@Query` で持つ。
  @Query(sort: \Snippet.updatedAt, order: .reverse) private var snippets: [Snippet]
  /// 一覧と見出しに出すスニペットグループを識別子から引くためのすべてのグループ。
  @Query private var snippetGroups: [SnippetGroup]
  /// 見出しに出すフォルダ名を識別子から引くためのすべてのフォルダ。
  @Query private var folders: [Folder]
  /// 見出しに出すタグ名を識別子から引くためのすべてのタグ。
  @Query private var tags: [Tag]
  /// 削除・検索と、コピーした時の使った日時の記録に使う。
  @Environment(\.modelContext) private var modelContext
  /// 意味検索の埋め込みモデルとベクトル。
  @Environment(SnippetEmbeddingController.self) private var snippetEmbeddingController
  /// 検索欄の入力。
  @State private var searchText = ""
  /// 検索欄に入力がある時の検索の結果の識別子 (一致の強い順)。
  ///
  /// 検索は意味検索の推論を含み重いため、描画のたびではなく `.task(id:)` で入力が止まった時だけ行い、結果をここに持つ (Mac の管理ウィンドウの一覧と同じ)。
  /// 検索の後に消されたスニペットを参照しないよう、モデルではなく識別子で持ち、描画の時に `snippets` から引く。
  @State private var searchedSnippetIDs: [UUID] = []
  /// 編集画面を出しているもの。
  @State private var snippetEditor: SnippetEditorTarget?
  /// 最後にコピーしたスニペットの名前。コピーしたことを知らせる表示に使う。
  @State private var copiedSnippetTitle: String?
  /// コピーした回数。同じ行を続けてタップした時も、表示の時間を測り直して触覚で知らせるため。
  @State private var copyCount = 0
  /// 削除の保存の失敗。
  @State private var errorMessage: String?

  var body: some View {
    let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let listedSnippets =
      isSearching ? searchedSnippetIDs.compactMap { snippetID in snippets.first { $0.id == snippetID } } : unsearchedSnippets
    List {
      ForEach(listedSnippets) { snippet in
        snippetRow(snippet: snippet)
      }
    }
    .overlay {
      if listedSnippets.isEmpty {
        if isSearching {
          ContentUnavailableView.search(text: searchText.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
          ContentUnavailableView("No Snippets", systemImage: "rectangle.portrait", description: Text("Tap + to add a snippet"))
        }
      }
    }
    .overlay(alignment: .bottom) {
      if let copiedSnippetTitle {
        Label {
          Text("Copied “\(copiedSnippetTitle)”")
        } icon: {
          Image(systemName: "checkmark.circle.fill")
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .padding(.bottom, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task(id: copyCount) {
          // 2 秒はコピーしたスニペットの名前を読み終えられる程度の長さ。キャンセル (続けてコピーした) の時は次のコピーの表示を消さない。
          guard (try? await Task.sleep(for: .seconds(2))) != nil else {
            return
          }
          withAnimation {
            self.copiedSnippetTitle = nil
          }
        }
      }
    }
    .sensoryFeedback(.success, trigger: copyCount)
    .searchable(text: $searchText, prompt: Text("Search by keyword or meaning"))
    .task(
      id: SnippetSearchTaskID(
        query: searchText,
        sidebarItem: sidebarItem,
        snippetIDs: snippets.map(\.id),
        snippetUpdatedAts: snippets.map(\.updatedAt),
        snippetGroupUpdatedAts: snippetGroups.map(\.updatedAt),
        snippetEmbeddingRevision: snippetEmbeddingController.revision
      )
    ) {
      guard isSearching else {
        searchedSnippetIDs = []
        return
      }
      // 入力の 1 文字ごとに意味検索の推論を走らせないよう、入力が止まってから検索する。250 ミリ秒は Mac の管理ウィンドウと同じで、打鍵の間隔 (1 文字あたりおよそ 100〜200 ミリ秒) より長く、止めてから結果が出るまでの遅れに気づきにくい長さ。
      do {
        try await Task.sleep(for: .milliseconds(250))
      } catch {
        return
      }
      let embedder = await snippetEmbeddingController.queryEmbedder(query: searchText)
      // 推論を待つ間に入力が変わって取り消された検索は、新しい入力の検索に任せる。
      guard !Task.isCancelled else {
        return
      }
      // 検索に失敗した時 (ストアの読み込みの失敗) は、誤った結果を出さないよう空の一覧にする。
      searchedSnippetIDs = ((try? searchedSnippets(embedder: embedder)) ?? []).map(\.id)
    }
    .navigationTitle(navigationTitle)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("New Snippet", systemImage: "plus") {
          snippetEditor = SnippetEditorTarget(snippet: nil, sidebarItem: sidebarItem)
        }
      }
      #if DEBUG
        ToolbarItem(placement: .secondaryAction) {
          DeveloperMenu()
        }
      #endif
    }
    .sheet(item: $snippetEditor) { snippetEditor in
      SnippetEditorView(snippet: snippetEditor.snippet, initialSidebarItem: snippetEditor.sidebarItem)
    }
    .alert("Could not delete", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
      Button("OK") {}
    } message: {
      Text(verbatim: errorMessage ?? "")
    }
  }

  /// 一覧の 1 行。タップでコピーし、スワイプと長押しで編集・削除・共有する。
  private func snippetRow(snippet: Snippet) -> some View {
    Button {
      copySnippetBodyAndRecordUse(snippet: snippet, modelContext: modelContext)
      withAnimation {
        copiedSnippetTitle = snippetDisplayTitle(snippet: snippet)
      }
      copyCount += 1
      selectedSnippetID?.wrappedValue = snippet.id
    } label: {
      SnippetRow(snippet: snippet)
    }
    .foregroundStyle(.primary)
    .listRowBackground(selectedSnippetID?.wrappedValue == snippet.id ? Color.accentColor.opacity(0.15) : nil)
    .swipeActions(edge: .trailing) {
      Button("Delete", systemImage: "trash", role: .destructive) {
        delete(snippet: snippet)
      }
      Button("Edit", systemImage: "pencil") {
        snippetEditor = SnippetEditorTarget(snippet: snippet, sidebarItem: sidebarItem)
      }
      .tint(.accentColor)
    }
    .contextMenu {
      Button("Copy", systemImage: "doc.on.doc") {
        copySnippetBodyAndRecordUse(snippet: snippet, modelContext: modelContext)
      }
      Button("Edit", systemImage: "pencil") {
        snippetEditor = SnippetEditorTarget(snippet: snippet, sidebarItem: sidebarItem)
      }
      ShareLink(item: snippet.body)
      Button("Delete", systemImage: "trash", role: .destructive) {
        delete(snippet: snippet)
      }
    }
  }

  /// 検索欄が空の時の一覧。ライブラリ・フォルダ・タグは更新日時の新しい順、スニペットグループはメニューに並べる順。
  private var unsearchedSnippets: [Snippet] {
    switch sidebarItem {
    case .library(let filter):
      snippets.filter { snippetMatchesLibraryFilter(snippet: $0, filter: filter) }
    case .snippetGroup(let snippetGroupID):
      snippetGroups.first { $0.id == snippetGroupID }.map { sortedSnippetGroupItems(snippetGroup: $0).compactMap(\.snippet) } ?? []
    }
  }

  /// 検索欄の入力で、サイドバーで選んだ行の中を検索した結果。
  private func searchedSnippets(embedder: SnippetTextEmbedder?) throws -> [Snippet] {
    switch sidebarItem {
    case .library(let filter):
      return try filteredSnippets(query: searchText, filter: filter, snippets: snippets, modelContext: modelContext, embedder: embedder)
    case .snippetGroup(let snippetGroupID):
      guard let snippetGroup = snippetGroups.first(where: { $0.id == snippetGroupID }) else {
        return []
      }
      return try filteredSnippetGroupSnippets(query: searchText, snippetGroup: snippetGroup, modelContext: modelContext, embedder: embedder)
    }
  }

  /// 画面の題。サイドバーで選んだ行の名前。
  private var navigationTitle: Text {
    switch sidebarItem {
    case .library(.all):
      Text("All Snippets")
    case .library(.folder(let folderID)):
      Text(verbatim: folders.first { $0.id == folderID }?.name ?? "")
    case .library(.tag(let tagID)):
      Text(verbatim: tags.first { $0.id == tagID }?.name ?? "")
    case .snippetGroup(let snippetGroupID):
      Text(verbatim: snippetGroups.first { $0.id == snippetGroupID }?.name ?? "")
    }
  }

  /// スニペットを消して保存し、意味検索のベクトルを作り直させる。詳細の列に出していれば外す。
  private func delete(snippet: Snippet) {
    if selectedSnippetID?.wrappedValue == snippet.id {
      selectedSnippetID?.wrappedValue = nil
    }
    modelContext.delete(snippet)
    errorMessage = saveSnippetChanges(modelContext: modelContext)
    if errorMessage == nil {
      Task {
        await snippetEmbeddingController.refreshEmbeddings()
      }
    }
  }
}

/// スニペットの編集画面 (sheet) で編集するもの。`sheet(item:)` に渡すため `Identifiable` にする。
struct SnippetEditorTarget: Identifiable {
  /// 編集するスニペット。`nil` は新規。
  let snippet: Snippet?
  /// 新規の時に、サイドバーで選んでいたフォルダ・タグを最初から入れておくため、選んでいた行を渡す。
  let sidebarItem: SnippetSidebarItem
  /// sheet を出すたびに別のものとして扱う識別子。新規は同じスニペットが無いため、毎回作る。
  let id = UUID()
}

/// 一覧の検索をやり直す条件。入力・サイドバーの行・スニペットの追加と更新と削除・スニペットグループの更新・意味検索のベクトルのどれかが変わったら検索し直す。
private struct SnippetSearchTaskID: Hashable {
  /// 検索欄に入力した文字列。
  let query: String
  /// サイドバーで選んだ行。
  let sidebarItem: SnippetSidebarItem
  /// すべてのスニペットの識別子。追加・削除で変わる。
  let snippetIDs: [UUID]
  /// すべてのスニペットの更新日時。更新で変わる。
  let snippetUpdatedAts: [Date]
  /// すべてのスニペットグループの更新日時。グループの項目を変えるとスニペットは変わらずに更新日時だけが変わる。
  let snippetGroupUpdatedAts: [Date]
  /// 意味検索のベクトルを作り直した回数 (`SnippetEmbeddingController.revision`)。
  let snippetEmbeddingRevision: Int
}

/// 一覧の 1 行の中身。色の帯・名前・更新日・本文の 1 行目・キーワードを並べる (`documents/design/Manager.dc.html` の一覧の行)。
struct SnippetRow: View {
  /// 行のスニペット。
  var snippet: Snippet

  var body: some View {
    HStack(spacing: 10) {
      SnippetColorBand(snippet: snippet)
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline) {
          Text(verbatim: snippetDisplayTitle(snippet: snippet))
            .font(.subheadline.weight(.semibold))
          Spacer(minLength: 8)
          Text(snippet.updatedAt, format: .dateTime.month().day())
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Text(verbatim: snippetBodyFirstLine(body: snippet.body))
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
        if let keyword = snippet.keyword {
          Text(verbatim: keyword)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
      .lineLimit(1)
    }
    .padding(.vertical, 2)
  }
}
