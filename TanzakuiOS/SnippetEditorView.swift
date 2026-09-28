import SwiftData
import SwiftUI
import TanzakuKit

/// スニペットの追加・編集の画面 (sheet)。Mac の管理ウィンドウと同じ項目 (本文・言語・タイトル・キーワード・フォルダ・タグ・色) を並べる (`documents/design/Manager.dc.html` の右側)。
///
/// `@Model` を直接書き換え、保存で `saveEditedSnippet(snippet:modelContext:now:)` の検査を通った時だけ保存する。
/// 保存していない変更は、この画面を出した側が sheet の `onDismiss` で `rollback()` して捨てる。取り消し・下へのスワイプのどちらで閉じても検査を通っていない値を残さないためと、
/// 出した側が閉じた後にほかの保存 (意味検索のベクトル) をする前に捨てるため。`modelContext` の自動保存は切ってある (`makeIOSModelContainer()`)。
struct SnippetEditorView: View {
  /// 編集するスニペット。追加の時は `modelContext` に入れたばかりの本文が空のもの。
  @Bindable var snippet: Snippet
  /// 追加か。画面の題を変える。
  var isNewSnippet: Bool

  /// 保存と取り消しに使う。
  @Environment(\.modelContext) private var modelContext
  /// 画面を閉じる。
  @Environment(\.dismiss) private var dismiss
  /// フォルダの選択肢。名前の順。
  @Query(sort: \Folder.name) private var folders: [Folder]
  /// タグの選択肢。名前の順。
  @Query(sort: \Tag.name) private var tags: [Tag]
  /// 足すタグの名前の入力。
  @State private var newTagName = ""
  /// 新しいフォルダの名前を聞いているか。
  @State private var isAskingNewFolderName = false
  /// 新しいフォルダの名前の入力。
  @State private var newFolderName = ""
  /// 保存の検査・保存の失敗。
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      Form {
        Section("Body") {
          TextEditor(text: $snippet.body)
            .font(.callout.monospaced())
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .frame(minHeight: 160)
            .accessibilityLabel(Text("Body"))
          Picker("Language", selection: $snippet.language) {
            Text("Plain Text")
              .tag(String?.none)
            ForEach(SnippetLanguage.allCases, id: \.self) { language in
              Text(verbatim: language.displayName)
                .tag(String?.some(language.rawValue))
            }
          }
        }
        Section {
          TextField("Title", text: optionalTextBinding(text: $snippet.title), prompt: Text("Uses the first line of the body"))
          TextField("Keyword", text: optionalTextBinding(text: $snippet.keyword), prompt: Text("Keyword"))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
        Section("Folder") {
          Picker("Folder", selection: $snippet.folder) {
            Text("None")
              .tag(Folder?.none)
            ForEach(folders) { folder in
              Text(verbatim: folder.name)
                .tag(Folder?.some(folder))
            }
          }
          Button("New Folder", systemImage: "folder.badge.plus") {
            newFolderName = ""
            isAskingNewFolderName = true
          }
        }
        Section("Tags") {
          ForEach(tags) { tag in
            Button {
              toggleTag(tag: tag)
            } label: {
              HStack {
                Text(verbatim: tag.name)
                  .foregroundStyle(.primary)
                Spacer()
                if snippet.tags?.contains(where: { $0.id == tag.id }) == true {
                  Image(systemName: "checkmark")
                }
              }
            }
          }
          TextField("Add a Tag", text: $newTagName)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit(addNewTag)
        }
        Section("Color") {
          SnippetColorPicker(colorRawValue: $snippet.colorRawValue)
        }
        if !isNewSnippet {
          Section {
            SnippetAuthorshipView(snippet: snippet)
          }
        }
      }
      .navigationTitle(isNewSnippet ? Text("New Snippet") : Text("Edit Snippet"))
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
      .alert("New Folder", isPresented: $isAskingNewFolderName) {
        TextField("Folder Name", text: $newFolderName)
        Button("Cancel", role: .cancel) {}
        Button("Add") {
          do {
            if let folder = try findOrInsertFolder(name: newFolderName, modelContext: modelContext) {
              snippet.folder = folder
            }
          } catch {
            errorMessage = String(describing: error)
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

  /// 検査を通れば保存して閉じる。通らなければ理由を出し、編集を続けさせる。
  private func save() {
    do {
      try saveEditedSnippet(snippet: snippet, modelContext: modelContext, now: .now)
      dismiss()
    } catch {
      errorMessage = String(describing: error)
    }
  }

  /// タグが付いていれば外し、付いていなければ付ける。
  private func toggleTag(tag: Tag) {
    if snippet.tags?.contains(where: { $0.id == tag.id }) == true {
      snippet.tags?.removeAll { $0.id == tag.id }
    } else {
      snippet.tags = (snippet.tags ?? []) + [tag]
    }
  }

  /// 入力した名前のタグを付ける。同じ名前のタグがあればそれを使う。
  private func addNewTag() {
    do {
      if let tag = try findOrInsertTag(name: newTagName, modelContext: modelContext), snippet.tags?.contains(where: { $0.id == tag.id }) != true {
        snippet.tags = (snippet.tags ?? []) + [tag]
      }
      newTagName = ""
    } catch {
      errorMessage = String(describing: error)
    }
  }
}

/// 任意の文字列の属性を `TextField` で書き換えるための `Binding`。空欄は保存の時に `nil` にする (`saveEditedSnippet(snippet:modelContext:now:)`)。
func optionalTextBinding(text: Binding<String?>) -> Binding<String> {
  Binding {
    text.wrappedValue ?? ""
  } set: {
    text.wrappedValue = $0
  }
}

/// 色の帯の色を選ぶ。色なしと 5 色を並べる (`documents/design/Manager.dc.html` の「色」)。
private struct SnippetColorPicker: View {
  /// 選んでいる色の raw value。`nil` は色なし。
  @Binding var colorRawValue: String?

  var body: some View {
    HStack(spacing: 14) {
      colorButton(snippetColor: nil)
      ForEach(SnippetColor.allCases, id: \.self) { snippetColor in
        colorButton(snippetColor: snippetColor)
      }
    }
    .padding(.vertical, 4)
  }

  /// 色の選択肢の 1 つ。選んでいる色は枠で囲む。
  private func colorButton(snippetColor: SnippetColor?) -> some View {
    Button {
      colorRawValue = snippetColor?.rawValue
    } label: {
      RoundedRectangle(cornerRadius: 3)
        .fill(snippetColor.map { snippetBandColor(snippetColor: $0) } ?? Color.clear)
        .overlay {
          if snippetColor == nil {
            Image(systemName: "slash.circle")
              .foregroundStyle(.secondary)
          }
        }
        .frame(width: 18, height: 28)
        .padding(3)
        .overlay(
          RoundedRectangle(cornerRadius: 5)
            .strokeBorder(colorRawValue == snippetColor?.rawValue ? Color.accentColor : .clear, lineWidth: 2)
        )
    }
    .buttonStyle(.plain)
    .accessibilityLabel(snippetColor.map { Text(snippetColorName(snippetColor: $0)) } ?? Text("No Color"))
    .accessibilityAddTraits(colorRawValue == snippetColor?.rawValue ? .isSelected : [])
  }
}
