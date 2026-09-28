import SwiftData
import SwiftUI
import TanzakuKit

/// スニペットグループの追加・編集の画面 (sheet)。名前・キーワードと、メニューに並べるスニペットとその順を決める。
///
/// 保存していない変更は、この画面を出した側が sheet の `onDismiss` で `rollback()` して捨てる (`SnippetEditorView` と同じ)。
struct SnippetGroupEditorView: View {
  /// 編集するスニペットグループ。追加の時は `modelContext` に入れたばかりの名前が空のもの。
  @Bindable var snippetGroup: SnippetGroup
  /// 追加か。画面の題を変える。
  var isNewSnippetGroup: Bool

  /// 保存に使う。
  @Environment(\.modelContext) private var modelContext
  /// 画面を閉じる。
  @Environment(\.dismiss) private var dismiss
  /// メニューに並べるスニペット。並べ替えと追加・削除はここで行い、保存の時にグループの項目へ書き込む。
  @State private var menuSnippets: [Snippet]
  /// 保存の検査・保存の失敗。
  @State private var errorMessage: String?

  /// メニューに並べるスニペットの初期値を今のグループの項目から作るため、init を書く。`onAppear` で作ると、スニペットを足す画面から戻るたびに足したものが消えるため。
  init(snippetGroup: SnippetGroup, isNewSnippetGroup: Bool) {
    self.snippetGroup = snippetGroup
    self.isNewSnippetGroup = isNewSnippetGroup
    _menuSnippets = State(initialValue: snippetGroupSnippets(snippetGroup: snippetGroup))
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Name", text: $snippetGroup.name)
          TextField("Keyword", text: optionalTextBinding(text: $snippetGroup.keyword), prompt: Text("Keyword (e.g. ;focus-app)"))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        } footer: {
          Text("Type the keyword on Mac to show a menu of these snippets")
        }
        Section("Menu Items") {
          ForEach(menuSnippets) { snippet in
            HStack(spacing: 10) {
              SnippetColorBand(snippet: snippet)
                .frame(height: 20)
              Text(verbatim: snippetDisplayTitle(snippet: snippet))
                .lineLimit(1)
            }
          }
          .onMove { indices, newOffset in
            menuSnippets.move(fromOffsets: indices, toOffset: newOffset)
          }
          .onDelete { indices in
            menuSnippets.remove(atOffsets: indices)
          }
          NavigationLink {
            SnippetGroupItemPicker(excludedSnippetIDs: Set(menuSnippets.map(\.id))) { snippet in
              menuSnippets.append(snippet)
            }
          } label: {
            Label("Add Snippets", systemImage: "plus")
          }
        }
      }
      .environment(\.editMode, .constant(.active))
      .navigationTitle(isNewSnippetGroup ? Text("New Snippet Group") : Text("Edit Snippet Group"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            save()
          }
        }
      }
      .alert("Could not save", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
        Button("OK") {}
      } message: {
        Text(verbatim: errorMessage ?? "")
      }
    }
  }

  /// メニューの項目を書き込み、検査を通れば保存して閉じる。通らなければ理由を出し、編集を続けさせる。
  private func save() {
    replaceSnippetGroupItems(snippetGroup: snippetGroup, snippets: menuSnippets, modelContext: modelContext)
    do {
      try saveEditedSnippetGroup(snippetGroup: snippetGroup, modelContext: modelContext, now: .now)
      dismiss()
    } catch {
      errorMessage = String(describing: error)
    }
  }
}

/// スニペットグループに足すスニペットを選ぶ一覧。選ぶたびに `onSelect` を呼び、選んだものは一覧から外す。
private struct SnippetGroupItemPicker: View {
  /// 既にメニューにあるスニペット。一覧に出さない。
  var excludedSnippetIDs: Set<UUID>
  /// スニペットを選んだ時に呼ぶ。
  var onSelect: (Snippet) -> Void

  /// すべてのスニペット。更新日時の新しい順。
  @Query(sort: \Snippet.updatedAt, order: .reverse) private var snippets: [Snippet]

  var body: some View {
    List {
      ForEach(snippets.filter { !excludedSnippetIDs.contains($0.id) }) { snippet in
        Button {
          onSelect(snippet)
        } label: {
          SnippetRow(snippet: snippet)
        }
        .foregroundStyle(.primary)
      }
    }
    .overlay {
      if snippets.allSatisfy({ excludedSnippetIDs.contains($0.id) }) {
        ContentUnavailableView("No Snippets to Add", systemImage: "rectangle.portrait")
      }
    }
    .navigationTitle(Text("Add Snippets"))
  }
}
