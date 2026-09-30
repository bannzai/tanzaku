import SwiftData
import SwiftUI
import TanzakuKit

/// 無料版で保存できるスニペットの件数 (`documents/PROJECT.md`「ライセンス」)。購入の判定はライセンスの issue ( https://github.com/bannzai/tanzaku/issues/20 ) で作り、ここでは件数の表示だけに使う。
let freeSnippetLimit = 20

/// 管理ウィンドウのサイドバー。ライブラリ (すべて・AI エージェントが追加・スニペットグループ)、フォルダ、タグと、無料版の件数を出す。
struct ManagerSidebar: View {
  /// サイドバーで選んでいる項目。
  @Binding var selection: ManagerSidebarSelection?
  @Environment(\.modelContext) private var modelContext
  /// 件数を数えるためのすべてのスニペット。
  @Query private var snippets: [Snippet]
  /// 名前の順のすべてのフォルダ。
  @Query(sort: \Folder.name) private var folders: [Folder]
  /// 名前の順のすべてのタグ。
  @Query(sort: \Tag.name) private var tags: [Tag]
  /// 件数を数えるためのすべてのスニペットグループ。
  @Query private var snippetGroups: [SnippetGroup]
  /// フォルダ・タグの削除の保存に失敗した理由。アラートで出す。
  @State private var saveErrorMessage: String?

  var body: some View {
    List(selection: $selection) {
      Section("Library") {
        sidebarRow(title: Text("All Snippets"), systemImage: "doc.plaintext", count: snippets.count)
          .tag(ManagerSidebarSelection.snippets(filter: .all))
          .accessibilityIdentifier("sidebar-all-snippets")
        sidebarRow(
          title: Text("Added by AI Agents"),
          systemImage: "sparkles",
          count: snippets.filter { snippetMatchesLibraryFilter(snippet: $0, filter: .addedByAgent) }.count
        )
        .tag(ManagerSidebarSelection.snippets(filter: .addedByAgent))
        .accessibilityIdentifier("sidebar-added-by-agents")
        sidebarRow(title: Text("Snippet Groups"), systemImage: "list.bullet.rectangle", count: snippetGroups.count)
          .tag(ManagerSidebarSelection.snippetGroups)
          .accessibilityIdentifier("sidebar-snippet-groups")
      }
      if !folders.isEmpty {
        Section("Folders") {
          ForEach(folders) { folder in
            sidebarRow(title: Text(verbatim: folder.name), systemImage: "folder", count: folder.snippets?.count ?? 0)
              .tag(ManagerSidebarSelection.snippets(filter: .folder(folderID: folder.id)))
              .contextMenu {
                Button("Delete Folder", role: .destructive) {
                  delete(model: folder, filter: .folder(folderID: folder.id))
                }
              }
          }
        }
      }
      if !tags.isEmpty {
        Section("Tags") {
          ForEach(tags) { tag in
            sidebarRow(title: Text(verbatim: tag.name), systemImage: "tag", count: tag.snippets?.count ?? 0)
              .tag(ManagerSidebarSelection.snippets(filter: .tag(tagID: tag.id)))
              .contextMenu {
                Button("Delete Tag", role: .destructive) {
                  delete(model: tag, filter: .tag(tagID: tag.id))
                }
              }
          }
        }
      }
    }
    .listStyle(.sidebar)
    .safeAreaInset(edge: .bottom) {
      freePlanFooter
    }
    .managerSaveErrorAlert(errorMessage: $saveErrorMessage)
  }

  /// サイドバーの 1 行。件数が 0 の時は数字を出さない。
  private func sidebarRow(title: Text, systemImage: String, count: Int) -> some View {
    Label {
      HStack {
        title
        Spacer()
        if count > 0 {
          Text(count, format: .number)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
      }
    } icon: {
      Image(systemName: systemImage)
    }
  }

  /// 無料版の件数と購入の導線。購入の処理はライセンスの issue で作るため、ボタンは表示だけ置く。
  private var freePlanFooter: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Free Plan")
        Spacer()
        Text("\(snippets.count) / \(freeSnippetLimit) snippets")
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      ProgressView(value: Double(min(snippets.count, freeSnippetLimit)), total: Double(freeSnippetLimit))
        .progressViewStyle(.linear)
      Button("Purchase a License…") {
        // 購入の処理はライセンスの issue ( https://github.com/bannzai/tanzaku/issues/20 ) で作る。
      }
      .buttonStyle(.link)
      .font(.caption)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
    .overlay(alignment: .top) {
      Divider()
    }
  }

  /// フォルダかタグを消す。スニペットは消さない (削除ルールは `.nullify`)。消したものを選んでいたら「すべてのスニペット」に戻す。保存に失敗したら削除を取り消して理由を出す。
  private func delete(model: some PersistentModel, filter: SnippetLibraryFilter) {
    if selection == .snippets(filter: filter) {
      selection = .snippets(filter: .all)
    }
    modelContext.delete(model)
    saveErrorMessage = saveManagerChanges(modelContext: modelContext)
  }
}
