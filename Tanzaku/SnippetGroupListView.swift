import SwiftData
import SwiftUI
import TanzakuKit

/// 管理ウィンドウのスニペットグループの一覧。検索欄の入力を名前かキーワードに含むものだけを出す。
struct SnippetGroupListView: View {
  /// 検索欄に入力した文字列。
  let searchText: String
  /// 一覧で選んでいる項目。
  @Binding var selection: ManagerDetailSelection?
  @Environment(\.modelContext) private var modelContext
  /// すべてのスニペットグループ。更新日時の新しい順。
  @Query(sort: \SnippetGroup.updatedAt, order: .reverse) private var snippetGroups: [SnippetGroup]
  /// 削除の確認を出しているスニペットグループ。
  @State private var deletingSnippetGroup: SnippetGroup?

  var body: some View {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    let listedSnippetGroups =
      query.isEmpty
      ? snippetGroups
      : snippetGroups.filter { $0.name.localizedStandardContains(query) || ($0.keyword ?? "").localizedStandardContains(query) }
    List(selection: $selection) {
      ForEach(Array(listedSnippetGroups.enumerated()), id: \.element.id) { index, snippetGroup in
        VStack(alignment: .leading, spacing: 4) {
          snippetGroupNameText(snippetGroup: snippetGroup)
            .font(.headline)
            .lineLimit(1)
          HStack {
            if let keyword = snippetGroup.keyword {
              Text(verbatim: keyword)
            }
            Spacer()
            Text("\(snippetGroup.items?.count ?? 0) snippets")
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .tag(ManagerDetailSelection.snippetGroup(snippetGroupID: snippetGroup.id))
        .accessibilityIdentifier("snippet-group-row-\(index)")
        .contextMenu {
          Button("Delete…", role: .destructive) {
            deletingSnippetGroup = snippetGroup
          }
        }
      }
    }
    .onDeleteCommand {
      if case .snippetGroup(let snippetGroupID) = selection {
        deletingSnippetGroup = snippetGroups.first { $0.id == snippetGroupID }
      }
    }
    .navigationTitle(Text("Snippet Groups"))
    .navigationSubtitle(Text("\(listedSnippetGroups.count) snippet groups"))
    .snippetGroupDeleteConfirmation(deletingSnippetGroup: $deletingSnippetGroup, selection: $selection)
  }
}

/// スニペットグループの表示名。名前は任意のため、無ければキーワード、それも無ければ「名称未設定」を出す。
func snippetGroupNameText(snippetGroup: SnippetGroup) -> Text {
  if !snippetGroup.name.isEmpty {
    return Text(verbatim: snippetGroup.name)
  }
  if let keyword = snippetGroup.keyword {
    return Text(verbatim: keyword)
  }
  return Text("Untitled Snippet Group")
}

extension View {
  /// スニペットグループの削除の確認を出し、確かめたら消す。グループに入れたスニペットは消さない。消したグループを選んでいたら選択を外す。
  func snippetGroupDeleteConfirmation(deletingSnippetGroup: Binding<SnippetGroup?>, selection: Binding<ManagerDetailSelection?>) -> some View {
    modifier(SnippetGroupDeleteConfirmation(deletingSnippetGroup: deletingSnippetGroup, selection: selection))
  }
}

/// `snippetGroupDeleteConfirmation(deletingSnippetGroup:selection:)` の本体。削除にストアが要るため、`@Environment` を持てる `ViewModifier` にする。
private struct SnippetGroupDeleteConfirmation: ViewModifier {
  /// 削除の確認を出しているスニペットグループ。
  @Binding var deletingSnippetGroup: SnippetGroup?
  /// 一覧で選んでいる項目。
  @Binding var selection: ManagerDetailSelection?
  @Environment(\.modelContext) private var modelContext

  func body(content: Content) -> some View {
    content.confirmationDialog(
      "Delete this snippet group?",
      isPresented: Binding(
        get: { deletingSnippetGroup != nil },
        set: { isPresented in
          if !isPresented {
            deletingSnippetGroup = nil
          }
        }
      ),
      presenting: deletingSnippetGroup
    ) { snippetGroup in
      Button("Delete", role: .destructive) {
        if selection == .snippetGroup(snippetGroupID: snippetGroup.id) {
          selection = nil
        }
        modelContext.delete(snippetGroup)
        try? modelContext.save()
        deletingSnippetGroup = nil
      }
    } message: { snippetGroup in
      Text("The snippets in \(snippetGroupNameText(snippetGroup: snippetGroup)) are not deleted.")
    }
  }
}
