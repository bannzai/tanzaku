import SwiftData
import SwiftUI
import TanzakuKit

/// 管理ウィンドウのスニペットの一覧。サイドバーの絞り込みと検索欄の結果を出す。
struct SnippetListView: View {
  /// サイドバーで選んだ絞り込み。
  let filter: SnippetLibraryFilter
  /// 検索欄に入力した文字列。
  let searchText: String
  /// 検索の入力から意味検索に使う埋め込みモデルを作る。`nil` を返した時は意味検索なしで検索する。
  let semanticQueryEmbedder: (String) async -> SnippetTextEmbedder?
  /// スニペットを削除した後に呼び、意味検索のベクトルを作り直させる。
  let onSnippetsChange: () -> Void
  /// 一覧で選んでいる項目。
  @Binding var selection: ManagerDetailSelection?
  @Environment(\.modelContext) private var modelContext
  /// 意味検索のベクトルを作り直した回数。埋め込みモデルの用意が済んだ時とベクトルを作り直した時に検索し直すため。
  @Environment(SnippetEmbeddingRevision.self) private var snippetEmbeddingRevision
  /// すべてのスニペット。スニペットの追加・更新・削除で一覧を描き直すため `@Query` で持つ。
  @Query(sort: \Snippet.updatedAt, order: .reverse) private var snippets: [Snippet]
  /// 見出しに出すフォルダ名を探すためのすべてのフォルダ。
  @Query private var folders: [Folder]
  /// 見出しに出すタグ名を探すためのすべてのタグ。
  @Query private var tags: [Tag]
  /// 削除の確認を出しているスニペット。
  @State private var deletingSnippet: Snippet?
  /// 検索欄に入力がある時の検索の結果の識別子 (一致の強い順)。
  ///
  /// 検索は意味検索の推論を含み重いため、描画のたびではなく `.task(id:)` で入力が止まった時だけ行い、結果をここに持つ。入力のベクトルの推論は `semanticQueryEmbedder` がメインスレッドの外で行う。
  /// 検索の後に消されたスニペットを参照しないよう、モデルではなく識別子で持ち、描画の時に `snippets` から引く。
  @State private var searchedSnippetIDs: [UUID] = []

  var body: some View {
    let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let listedSnippets =
      isSearching
      ? searchedSnippetIDs.compactMap { snippetID in snippets.first { $0.id == snippetID } }
      : snippets.filter { snippetMatchesLibraryFilter(snippet: $0, filter: filter) }
    List(selection: $selection) {
      ForEach(Array(listedSnippets.enumerated()), id: \.element.id) { index, snippet in
        SnippetRow(snippet: snippet)
          .tag(ManagerDetailSelection.snippet(snippetID: snippet.id))
          .accessibilityIdentifier("snippet-row-\(index)")
          .contextMenu {
            Button("Delete…", role: .destructive) {
              deletingSnippet = snippet
            }
          }
      }
    }
    // macOS の List は足した行の高さを 1 行分に潰して描き、測り直さなかった (ローカルの Debug ビルドで新規作成した直後に再現。
    // 行の中身をそろえる・選ぶ時機をずらすのでは直らなかった)。出す行が変わったら List を作り直して、すべての行を測り直させる。
    // 検索の結果も描画の後に届いて行が変わるため、件数ではなく出す行の並びで作り直す。
    .id(listedSnippets.map(\.id))
    .task(
      id: SnippetSearchTaskID(
        query: searchText,
        filter: filter,
        snippetIDs: snippets.map(\.id),
        snippetUpdatedAts: snippets.map(\.updatedAt),
        snippetEmbeddingRevision: snippetEmbeddingRevision.value
      )
    ) {
      guard isSearching else {
        searchedSnippetIDs = []
        return
      }
      // 入力の 1 文字ごとに意味検索の推論を走らせないよう、入力が止まってから検索する。250 ミリ秒は、打鍵の間隔 (1 文字あたりおよそ 100〜200 ミリ秒) より長く、止めてから結果が出るまでの遅れに気づきにくい長さ。
      do {
        try await Task.sleep(for: .milliseconds(250))
      } catch {
        return
      }
      let embedder = await semanticQueryEmbedder(searchText)
      // 推論を待つ間に入力が変わって取り消された検索は、新しい入力の検索に任せる。
      guard !Task.isCancelled else {
        return
      }
      // 検索に失敗した時 (ストアの読み込みの失敗) は、誤った結果を出さないよう空の一覧にする。
      searchedSnippetIDs =
        ((try? filteredSnippets(query: searchText, filter: filter, snippets: snippets, modelContext: modelContext, embedder: embedder)) ?? [])
        .map(\.id)
    }
    .onDeleteCommand {
      if case .snippet(let snippetID) = selection {
        deletingSnippet = snippets.first { $0.id == snippetID }
      }
    }
    .navigationTitle(title)
    .navigationSubtitle(Text("\(listedSnippets.count) snippets"))
    .snippetDeleteConfirmation(deletingSnippet: $deletingSnippet, onSnippetsChange: onSnippetsChange, selection: $selection)
  }

  /// 一覧の見出し。サイドバーで選んだ項目の名前。
  private var title: Text {
    switch filter {
    case .all:
      Text("All Snippets")
    case .addedByAgent:
      Text("Added by AI Agents")
    case .folder(let folderID):
      Text(verbatim: folders.first { $0.id == folderID }?.name ?? "")
    case .tag(let tagID):
      Text(verbatim: tags.first { $0.id == tagID }?.name ?? "")
    }
  }
}

/// 一覧の検索をやり直す条件。入力・絞り込み・スニペットの追加と更新と削除・意味検索のベクトルのどれかが変わったら検索し直す。
private struct SnippetSearchTaskID: Hashable {
  /// 検索欄に入力した文字列。
  let query: String
  /// サイドバーで選んだ絞り込み。
  let filter: SnippetLibraryFilter
  /// すべてのスニペットの識別子。追加・削除で変わる。
  let snippetIDs: [UUID]
  /// すべてのスニペットの更新日時。更新で変わる。
  let snippetUpdatedAts: [Date]
  /// 意味検索のベクトルを作り直した回数 (`SnippetEmbeddingRevision.value`)。
  let snippetEmbeddingRevision: Int
}

/// スニペットの一覧の 1 行。色の帯・名前・更新日・本文の 1 行目・キーワード (`documents/design/Manager.dc.html`)。
private struct SnippetRow: View {
  /// 行に出すスニペット。
  let snippet: Snippet

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      RoundedRectangle(cornerRadius: 2)
        .fill(snippet.color.map { snippetBandColor(snippetColor: $0) } ?? .clear)
        .frame(width: 4, height: 40)
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline) {
          Text(verbatim: snippetDisplayTitle(snippet: snippet))
            .font(.headline)
            .lineLimit(1)
          Spacer()
          Text(snippet.updatedAt, format: .dateTime.month().day())
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Text(verbatim: snippetBodyFirstLine(body: snippet.body))
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        if let keyword = snippet.keyword {
          Text(verbatim: keyword)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(.vertical, 4)
  }
}

extension View {
  /// スニペットの削除の確認を出し、確かめたら消す。消したスニペットを選んでいたら選択を外す。
  func snippetDeleteConfirmation(
    deletingSnippet: Binding<Snippet?>,
    onSnippetsChange: @escaping () -> Void,
    selection: Binding<ManagerDetailSelection?>
  ) -> some View {
    modifier(SnippetDeleteConfirmation(deletingSnippet: deletingSnippet, onSnippetsChange: onSnippetsChange, selection: selection))
  }
}

/// `snippetDeleteConfirmation(deletingSnippet:onSnippetsChange:selection:)` の本体。削除にストアが要るため、`@Environment` を持てる `ViewModifier` にする。
private struct SnippetDeleteConfirmation: ViewModifier {
  /// 削除の確認を出しているスニペット。
  @Binding var deletingSnippet: Snippet?
  /// 削除の後に呼び、意味検索のベクトルを作り直させる。
  let onSnippetsChange: () -> Void
  /// 一覧で選んでいる項目。
  @Binding var selection: ManagerDetailSelection?
  @Environment(\.modelContext) private var modelContext

  func body(content: Content) -> some View {
    content.confirmationDialog(
      "Delete this snippet?",
      isPresented: Binding(get: { deletingSnippet != nil }, set: { isPresented in
        if !isPresented {
          deletingSnippet = nil
        }
      }),
      presenting: deletingSnippet
    ) { snippet in
      Button("Delete", role: .destructive) {
        if selection == .snippet(snippetID: snippet.id) {
          selection = nil
        }
        modelContext.delete(snippet)
        try? modelContext.save()
        onSnippetsChange()
        deletingSnippet = nil
      }
      .accessibilityIdentifier("confirm-delete-snippet-button")
    } message: { snippet in
      Text(verbatim: snippetDisplayTitle(snippet: snippet))
    }
  }
}
