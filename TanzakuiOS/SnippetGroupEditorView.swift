import SwiftData
import SwiftUI
import TanzakuKit

/// スニペットグループの追加・編集の画面 (sheet)。名前・キーワードと、メニューに並べるスニペットとその順を決める。
///
/// 入力を画面の状態に持ち、「保存」で検査を通った時だけ書き込む (`applySnippetGroupEdit`。Mac の編集画面と同じ)。
struct SnippetGroupEditorView: View {
  /// 編集するスニペットグループ。`nil` は新規。
  let snippetGroup: SnippetGroup?

  @Environment(\.modelContext) private var modelContext
  /// 画面を閉じる。
  @Environment(\.dismiss) private var dismiss
  /// メニューに足せるスニペット。更新日時の新しい順。
  @Query(sort: \Snippet.updatedAt, order: .reverse) private var snippets: [Snippet]
  /// 入力中の名前。
  @State private var name: String
  /// 入力中のキーワード。
  @State private var keyword: String
  /// メニューに並べる順のスニペットの識別子。編集中にスニペットが消されても消したモデルを参照しないよう、モデルではなく識別子で持ち、`snippets` から引く。
  @State private var groupSnippetIDs: [UUID]
  /// 保存の検査・保存の失敗。
  @State private var errorMessage: String?
  /// 新規作成の下書きのスニペットグループ。保存に失敗した時に取り消し、次の保存で新しい下書きを使う (Mac の編集画面と同じ)。
  @State private var draftSnippetGroup = SnippetGroup(name: "")

  /// 入力の初期値をスニペットグループから決めるため、`@State` の初期値を渡す。
  init(snippetGroup: SnippetGroup?) {
    self.snippetGroup = snippetGroup
    _name = State(initialValue: snippetGroup?.name ?? "")
    _keyword = State(initialValue: snippetGroup?.keyword ?? "")
    _groupSnippetIDs = State(initialValue: snippetGroup.map { sortedSnippetGroupItems(snippetGroup: $0).compactMap(\.snippet?.id) } ?? [])
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Name", text: $name)
          TextField("Keyword", text: $keyword, prompt: Text("Keyword (e.g. ;focus-app)"))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        } footer: {
          Text("Type the keyword on Mac to show a menu of these snippets")
        }
        Section("Menu Items") {
          ForEach(groupSnippets) { snippet in
            HStack(spacing: 10) {
              SnippetColorBand(snippet: snippet)
                .frame(height: 20)
              Text(verbatim: snippetDisplayTitle(snippet: snippet))
                .lineLimit(1)
            }
          }
          .onMove { indices, newOffset in
            // 並べ替えの位置は表示している (消されたスニペットを除いた) 並びの位置のため、表示している並びの識別子で置き換えてから動かす。
            groupSnippetIDs = groupSnippets.map(\.id)
            groupSnippetIDs.move(fromOffsets: indices, toOffset: newOffset)
          }
          .onDelete { indices in
            groupSnippetIDs = groupSnippets.map(\.id)
            groupSnippetIDs.remove(atOffsets: indices)
          }
          NavigationLink {
            SnippetGroupItemPicker(snippets: snippets.filter { !groupSnippetIDs.contains($0.id) }) { snippet in
              groupSnippetIDs.append(snippet.id)
            }
          } label: {
            Label("Add Snippets", systemImage: "plus")
          }
        }
      }
      .environment(\.editMode, .constant(.active))
      .navigationTitle(snippetGroup == nil ? Text("New Snippet Group") : Text("Edit Snippet Group"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save", action: save)
        }
      }
      .alert("Could not save", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
        Button("OK") {}
      } message: {
        Text(verbatim: errorMessage ?? "")
      }
    }
  }

  /// メニューに並べる順のスニペット。消されたスニペットは `snippets` に無いため除かれる。
  private var groupSnippets: [Snippet] {
    groupSnippetIDs.compactMap { snippetID in snippets.first { $0.id == snippetID } }
  }

  /// 入力を検査してスニペットグループに書き込み、保存して閉じる。検査・保存に失敗したら理由を出し、編集を続けさせる。
  private func save() {
    let editingSnippetGroup = snippetGroup ?? draftSnippetGroup
    do {
      try applySnippetGroupEdit(
        snippetGroup: editingSnippetGroup,
        name: name,
        keyword: keyword,
        snippets: groupSnippets,
        modelContext: modelContext,
        now: .now
      )
    } catch let validationError as SnippetValidationError {
      errorMessage = validationError.description
      return
    } catch {
      // 途中まで書き込んだ変更と新規の挿入を取り消す (理由は `SnippetEditorView.save()` と同じ)。
      modelContext.rollback()
      if snippetGroup == nil {
        draftSnippetGroup = SnippetGroup(name: "")
      }
      errorMessage = error.localizedDescription
      return
    }
    if let saveErrorMessage = saveSnippetChanges(modelContext: modelContext) {
      errorMessage = saveErrorMessage
      if snippetGroup == nil {
        draftSnippetGroup = SnippetGroup(name: "")
      }
      return
    }
    dismiss()
  }
}

/// スニペットグループに足すスニペットを選ぶ一覧。選ぶたびに `onSelect` を呼ぶ。選んだものは呼び出し側が `snippets` から外す。
private struct SnippetGroupItemPicker: View {
  /// 足せるスニペット。
  var snippets: [Snippet]
  /// スニペットを選んだ時に呼ぶ。
  var onSelect: (Snippet) -> Void

  var body: some View {
    List {
      ForEach(snippets) { snippet in
        Button {
          onSelect(snippet)
        } label: {
          SnippetRow(snippet: snippet)
        }
        .foregroundStyle(.primary)
      }
    }
    .overlay {
      if snippets.isEmpty {
        ContentUnavailableView("No Snippets to Add", systemImage: "rectangle.portrait")
      }
    }
    .navigationTitle(Text("Add Snippets"))
  }
}
