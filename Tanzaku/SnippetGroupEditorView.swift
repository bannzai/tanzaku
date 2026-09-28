import SwiftData
import SwiftUI
import TanzakuKit

/// スニペットグループの編集画面。名前・キーワードと、メニューに並べるスニペットの選択と並べ替え。
///
/// 入力を画面の状態に持ち、「保存」で検査を通った時だけ書き込む理由は `SnippetEditorView` と同じ。
struct SnippetGroupEditorView: View {
  /// 編集するスニペットグループ。`nil` は新規。
  let snippetGroup: SnippetGroup?
  /// 一覧で選んでいる項目。新規のグループを保存したら、そのグループを選ぶ。
  @Binding var selection: ManagerDetailSelection?
  @Environment(\.modelContext) private var modelContext
  /// 「スニペットを追加」のメニューに並べるスニペット。
  @Query(sort: \Snippet.updatedAt, order: .reverse) private var snippets: [Snippet]
  /// 入力中の名前。
  @State private var name: String
  /// 入力中のキーワード。
  @State private var keyword: String
  /// メニューに並べる順のスニペット。
  @State private var groupSnippets: [Snippet]
  /// 保存に失敗した理由。画面にそのまま出す。
  @State private var errorMessage: String?
  /// 削除の確認を出しているスニペットグループ。
  @State private var deletingSnippetGroup: SnippetGroup?

  /// 編集画面の入力の初期値をスニペットグループから決めるため、`@State` の初期値を渡す。
  init(snippetGroup: SnippetGroup?, selection: Binding<ManagerDetailSelection?>) {
    self.snippetGroup = snippetGroup
    _selection = selection
    _name = State(initialValue: snippetGroup?.name ?? "")
    _keyword = State(initialValue: snippetGroup?.keyword ?? "")
    _groupSnippets = State(initialValue: snippetGroup.map { sortedSnippetGroupItems(snippetGroup: $0).compactMap(\.snippet) } ?? [])
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
        GridRow {
          Text("Name")
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
          TextField("Name", text: $name)
            .labelsHidden()
            .accessibilityIdentifier("snippet-group-name-field")
        }
        GridRow {
          Text("Keyword")
            .foregroundStyle(.secondary)
          TextField("Keyword", text: $keyword)
            .labelsHidden()
            .frame(width: 160)
            .accessibilityIdentifier("snippet-group-keyword-field")
        }
      }
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("Snippets")
            .foregroundStyle(.secondary)
          Spacer()
          addSnippetMenu
        }
        List {
          ForEach(groupSnippets, id: \.id) { snippet in
            HStack(spacing: 10) {
              Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
              RoundedRectangle(cornerRadius: 2)
                .fill(snippet.color?.bandColor ?? .clear)
                .frame(width: 4, height: 18)
              Text(verbatim: snippetDisplayTitle(snippet: snippet))
                .lineLimit(1)
              Spacer()
              if let keyword = snippet.keyword {
                Text(verbatim: keyword)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Button {
                groupSnippets.removeAll { $0.id == snippet.id }
              } label: {
                Image(systemName: "minus.circle")
              }
              .buttonStyle(.borderless)
              .accessibilityLabel(Text("Remove from Snippet Group"))
            }
          }
          .onMove { source, destination in
            groupSnippets.move(fromOffsets: source, toOffset: destination)
          }
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
        .overlay {
          if groupSnippets.isEmpty {
            Text("Add snippets to show in the menu")
              .foregroundStyle(.secondary)
          }
        }
      }
      if let errorMessage {
        Text(verbatim: errorMessage)
          .foregroundStyle(.red)
          .accessibilityIdentifier("snippet-group-error-message")
      }
      HStack {
        Spacer()
        if let snippetGroup {
          Button("Delete…", role: .destructive) {
            deletingSnippetGroup = snippetGroup
          }
        }
        Button("Save", action: save)
          .keyboardShortcut("s")
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("snippet-group-save-button")
      }
    }
    .padding(.horizontal, 32)
    .padding(.vertical, 24)
    .snippetGroupDeleteConfirmation(deletingSnippetGroup: $deletingSnippetGroup, selection: $selection)
  }

  /// グループにまだ入れていないスニペットを選んで末尾に足すメニュー。
  private var addSnippetMenu: some View {
    Menu("Add Snippet") {
      ForEach(snippets.filter { snippet in !groupSnippets.contains { $0.id == snippet.id } }, id: \.id) { snippet in
        Button {
          groupSnippets.append(snippet)
        } label: {
          Text(verbatim: snippetDisplayTitle(snippet: snippet))
        }
      }
    }
    .fixedSize()
    .disabled(snippets.count == groupSnippets.count)
  }

  /// 入力を検査してスニペットグループに書き込み、保存する。新規のグループは保存できたら一覧で選ぶ。
  private func save() {
    let editingSnippetGroup = snippetGroup ?? SnippetGroup(name: "")
    do {
      try applySnippetGroupEdit(
        snippetGroup: editingSnippetGroup,
        name: name,
        keyword: keyword,
        snippets: groupSnippets,
        modelContext: modelContext,
        now: .now
      )
      try modelContext.save()
      errorMessage = nil
      if snippetGroup == nil {
        selection = .snippetGroup(snippetGroupID: editingSnippetGroup.id)
      }
    } catch let validationError as SnippetValidationError {
      errorMessage = validationError.description
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
