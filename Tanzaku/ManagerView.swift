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
  /// 新規のスニペット。保存するまでストアに入れないため、押すたびに編集画面を作り直すよう下書きごとの識別子を持つ。`title` はタイトルの入力の初期値 (ランチャーに入力した言葉)。
  /// `draftID` は保存した時にスニペットの識別子になり、選択は同じ識別子の `snippet` に変わる。保存の前後で同じ編集画面を出し続けるため。
  case newSnippet(draftID: UUID, title: String)
  /// 既存のスニペットグループ。
  case snippetGroup(snippetGroupID: UUID)
  /// 新規のスニペットグループ。識別子を持つ理由は `newSnippet` と同じ。
  case newSnippetGroup(draftID: UUID)
}

/// 管理ウィンドウ。サイドバー・一覧・編集の 3 列 (`documents/design/Manager.dc.html`)。
struct ManagerView: View {
  /// 検索の入力から意味検索に使う埋め込みモデルを作る。埋め込みモデルを用意できていない時は `nil` を返し、意味検索なしで検索する。
  let semanticQueryEmbedder: (String) async -> SnippetTextEmbedder?
  /// スニペットを保存・削除した後に呼び、意味検索のベクトルを作り直させる。
  let onSnippetsChange: () -> Void
  /// ランチャーの結果なしの画面から新規作成 (⌘N) に進んだ時の下書き。
  @Environment(NewSnippetDraft.self) private var newSnippetDraft
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
          SnippetListView(
            filter: filter,
            searchText: searchText,
            semanticQueryEmbedder: semanticQueryEmbedder,
            onSnippetsChange: onSnippetsChange,
            selection: $detailSelection
          )
        }
      }
      .navigationSplitViewColumnWidth(min: 280, ideal: 340)
      .searchable(text: $searchText, placement: .toolbar, prompt: Text("Search by keyword or meaning"))
      .toolbar {
        ToolbarItem {
          Button {
            detailSelection = sidebarSelection == .snippetGroups ? .newSnippetGroup(draftID: UUID()) : .newSnippet(draftID: UUID(), title: "")
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
      ManagerDetailView(selection: $detailSelection, onSnippetsChange: onSnippetsChange)
    }
    .onChange(of: sidebarSelection) {
      // ランチャーの下書きから始めた新規作成は、サイドバーを「すべてのスニペット」に切り替えた後も残す (`startNewSnippetFromDraft()`)。
      if case .newSnippet = detailSelection {
        return
      }
      detailSelection = nil
    }
    .onChange(of: newSnippetDraft.title, initial: true) {
      startNewSnippetFromDraft()
    }
  }

  /// ランチャーの下書きがあれば、そのタイトルを入れた新規作成を始めて下書きを空にする。下書きが無ければ何もしないため、何度呼んでも 1 回だけ始まる。
  ///
  /// スニペットグループの一覧を出している時は、スニペットの新規作成を出せるよう「すべてのスニペット」に切り替える。
  private func startNewSnippetFromDraft() {
    guard let draftTitle = newSnippetDraft.title else {
      return
    }
    newSnippetDraft.title = nil
    detailSelection = .newSnippet(draftID: UUID(), title: draftTitle)
    if sidebarSelection == .snippetGroups || sidebarSelection == nil {
      sidebarSelection = .snippets(filter: .all)
    }
  }
}

/// 管理ウィンドウでの変更を保存する。保存に失敗したら未保存の変更を取り消し、失敗の理由を返す (成功したら `nil`)。
///
/// 取り消すのは、消したはずのフォルダ・タグ・スニペットが画面から消えたまま、次に別の操作で保存された時に消えるのを防ぐため。
/// 編集中の入力は各編集画面の状態に持ち、ストアの未保存の変更には入っていないため、取り消しても入力は残る。
func saveManagerChanges(modelContext: ModelContext) -> String? {
  do {
    try modelContext.save()
    return nil
  } catch {
    modelContext.rollback()
    return error.localizedDescription
  }
}

/// スニペットがストアに入っているか。まだ保存していない新規のスニペットと、消したスニペットは `false`。
///
/// 消したスニペットの属性を読み書きすると落ちるため、編集を終えた時の保存や、言語モデルの応答を待った後の書き込みの前に確かめる。
func isSnippetInStore(snippet: Snippet) -> Bool {
  snippet.modelContext != nil && !snippet.isDeleted
}

extension View {
  /// 保存に失敗した理由をアラートで出す。`errorMessage` が `nil` でない間だけ出し、閉じると `nil` に戻す。
  func managerSaveErrorAlert(errorMessage: Binding<String?>) -> some View {
    alert(
      "Couldn't Save the Change",
      isPresented: Binding(
        get: { errorMessage.wrappedValue != nil },
        set: { isPresented in
          if !isPresented {
            errorMessage.wrappedValue = nil
          }
        }
      ),
      presenting: errorMessage.wrappedValue
    ) { _ in
      Button("OK", role: .cancel) {}
    } message: { message in
      Text(verbatim: message)
    }
  }
}

/// 一覧で選んだ項目の編集画面。
private struct ManagerDetailView: View {
  /// 一覧で選んでいる項目。
  @Binding var selection: ManagerDetailSelection?
  /// スニペットを保存・削除した後に呼び、意味検索のベクトルを作り直させる。
  let onSnippetsChange: () -> Void
  /// 保存した直後のスニペットを `snippets` より先に引くためのストア (`storedSnippet(snippetID:)`)。
  @Environment(\.modelContext) private var modelContext
  /// 選んだ識別子のスニペットを探すためのすべてのスニペット。
  @Query private var snippets: [Snippet]
  /// 選んだ識別子のスニペットグループを探すためのすべてのスニペットグループ。
  @Query private var snippetGroups: [SnippetGroup]
  /// スニペットの編集を終えた時 (別の項目を選んだ時など) の保存に失敗した理由。編集画面は消えているため、ここからアラートで出す。
  @State private var finishEditingErrorMessage: String?

  var body: some View {
    detail
      .managerSaveErrorAlert(errorMessage: $finishEditingErrorMessage)
  }

  /// 選んでいる項目の編集画面。何も選んでいなければ案内。
  @ViewBuilder
  private var detail: some View {
    switch selection {
    // 新規のスニペットは保存すると同じ識別子の `snippet` の選択に変わる。その前後で編集画面を作り直すと入力中のフォーカスが失われるため、2 つの選択を同じ場所・同じ識別子で出す。
    case .snippet(let snippetID), .newSnippet(let snippetID, _):
      let snippet = storedSnippet(snippetID: snippetID)
      if snippet != nil || newSnippetDraftTitle != nil {
        SnippetEditorView(
          snippet: snippet,
          snippetID: snippetID,
          // 既存のスニペットはタイトルをスニペットから読むため、下書きのタイトルは使わない。
          draftTitle: newSnippetDraftTitle ?? "",
          onSnippetsChange: onSnippetsChange,
          onFinishEditingFailure: { errorMessage in
            finishEditingErrorMessage = errorMessage
          },
          selection: $selection
        )
        .id(snippetID)
      } else {
        noSelectionView
      }
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

  /// 新規のスニペットを選んでいる時の、タイトルの入力の初期値。新規のスニペットを選んでいなければ `nil`。
  private var newSnippetDraftTitle: String? {
    if case .newSnippet(_, let title) = selection {
      return title
    }
    return nil
  }

  /// ストアにある `snippetID` のスニペット。無ければ `nil`。
  ///
  /// `@Query` の結果に無い時はストアから直接引く。新規のスニペットを自動保存でストアに入れた直後の描画で `@Query` の結果がまだ古いと、
  /// その 1 回の描画で編集画面が外れて入力中のフォーカスが失われるため。消したスニペットはどちらにも無い。
  private func storedSnippet(snippetID: UUID) -> Snippet? {
    snippets.first { $0.id == snippetID }
      ?? (try? modelContext.fetch(FetchDescriptor<Snippet>(predicate: #Predicate { $0.id == snippetID })))?.first
  }

  /// 何も選んでいない時の表示。
  private var noSelectionView: some View {
    Text("Select an item")
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
