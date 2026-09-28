import SwiftData
import SwiftUI
import TanzakuKit

/// 管理ウィンドウのスニペットの一覧。サイドバーの絞り込みと検索欄の結果を出す。
struct SnippetListView: View {
  /// サイドバーで選んだ絞り込み。
  let filter: SnippetLibraryFilter
  /// 検索欄に入力した文字列。
  let searchText: String
  /// 意味検索に使う埋め込みモデル。`nil` の時は意味検索なしで検索する。
  let embedder: SnippetTextEmbedder?
  /// 一覧で選んでいる項目。
  @Binding var selection: ManagerDetailSelection?
  @Environment(\.modelContext) private var modelContext
  /// すべてのスニペット。スニペットの追加・更新・削除で一覧を描き直すため `@Query` で持つ。
  @Query(sort: \Snippet.updatedAt, order: .reverse) private var snippets: [Snippet]
  /// 見出しに出すフォルダ名を探すためのすべてのフォルダ。
  @Query private var folders: [Folder]
  /// 見出しに出すタグ名を探すためのすべてのタグ。
  @Query private var tags: [Tag]
  /// 削除の確認を出しているスニペット。
  @State private var deletingSnippet: Snippet?

  var body: some View {
    // 検索に失敗した時 (ストアの読み込みの失敗) は、誤った結果を出さないよう空の一覧にする。
    let listedSnippets =
      (try? filteredSnippets(query: searchText, filter: filter, snippets: snippets, modelContext: modelContext, embedder: embedder)) ?? []
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
    // 行の中身をそろえる・選ぶ時機をずらすのでは直らなかった)。スニペットの件数が変わったら List を作り直して、すべての行を測り直させる。
    .id(snippets.count)
    .onDeleteCommand {
      if case .snippet(let snippetID) = selection {
        deletingSnippet = snippets.first { $0.id == snippetID }
      }
    }
    .navigationTitle(title)
    .navigationSubtitle(Text("\(listedSnippets.count) snippets"))
    .snippetDeleteConfirmation(deletingSnippet: $deletingSnippet, embedder: embedder, selection: $selection)
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

/// スニペットの一覧の 1 行。色の帯・名前・更新日・本文の 1 行目・キーワード (`documents/design/Manager.dc.html`)。
private struct SnippetRow: View {
  /// 行に出すスニペット。
  let snippet: Snippet

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      RoundedRectangle(cornerRadius: 2)
        .fill(snippet.color?.bandColor ?? .clear)
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
        Text(verbatim: snippet.body.split(whereSeparator: \.isNewline).first.map(String.init) ?? "")
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
    embedder: SnippetTextEmbedder?,
    selection: Binding<ManagerDetailSelection?>
  ) -> some View {
    modifier(SnippetDeleteConfirmation(deletingSnippet: deletingSnippet, embedder: embedder, selection: selection))
  }
}

/// `snippetDeleteConfirmation(deletingSnippet:embedder:selection:)` の本体。削除にストアが要るため、`@Environment` を持てる `ViewModifier` にする。
private struct SnippetDeleteConfirmation: ViewModifier {
  /// 削除の確認を出しているスニペット。
  @Binding var deletingSnippet: Snippet?
  /// 削除の後に意味検索のベクトルを合わせる埋め込みモデル。
  let embedder: SnippetTextEmbedder?
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
        try? saveSnippetChanges(modelContext: modelContext, embedder: embedder)
        deletingSnippet = nil
      }
      .accessibilityIdentifier("confirm-delete-snippet-button")
    } message: { snippet in
      Text(verbatim: snippetDisplayTitle(snippet: snippet))
    }
  }
}
