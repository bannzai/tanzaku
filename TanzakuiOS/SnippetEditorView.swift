import SwiftData
import SwiftUI
import TanzakuKit

/// スニペットの追加・編集の画面 (sheet)。Mac の管理ウィンドウと同じ項目 (本文・言語・タイトル・キーワード・フォルダ・タグ・色) を並べる (`documents/design/Manager.dc.html` の右側)。
///
/// 入力はこの画面の状態に持ち、「保存」で検査を通った時だけスニペットに書き込む (`applySnippetEdit`。Mac の編集画面と同じ)。
/// SwiftData は自動で保存するため、スニペットを直接書き換えると空の本文や重複したキーワードのまま保存されてしまうため。
struct SnippetEditorView: View {
  /// 編集するスニペット。`nil` は新規。
  let snippet: Snippet?

  @Environment(\.modelContext) private var modelContext
  /// 画面を閉じる。
  @Environment(\.dismiss) private var dismiss
  /// 保存の後に意味検索のベクトルを作り直させる。
  @Environment(SnippetEmbeddingController.self) private var snippetEmbeddingController
  /// フォルダの選択肢。名前の順。
  @Query(sort: \Folder.name) private var folders: [Folder]
  /// タグの選択肢。名前の順。
  @Query(sort: \Tag.name) private var tags: [Tag]
  /// 入力中の本文。
  @State private var bodyText: String
  /// 入力中のタイトル。
  @State private var title: String
  /// 入力中のキーワード。
  @State private var keyword: String
  /// 選んでいる言語 (`Snippet.language` の値)。`nil` はプレーンテキスト。
  @State private var language: String?
  /// 選んでいる色。`nil` は色なし。
  @State private var color: SnippetColor?
  /// 選んでいるフォルダの識別子。編集中にフォルダが消されても消したモデルを参照しないよう、モデルではなく識別子で持ち、`folders` から引く。
  @State private var folderID: UUID?
  /// 付けるタグの名前。
  @State private var tagNames: [String]
  /// タグの欄に入力中の、まだタグにしていない名前。
  @State private var newTagName = ""
  /// 新しいフォルダの名前を聞いているか。
  @State private var isCreatingFolder = false
  /// 新しいフォルダの名前の入力。
  @State private var newFolderName = ""
  /// 保存の検査・保存の失敗。
  @State private var errorMessage: String?
  /// 新規作成の下書きのスニペット。検査を通るとストアに入る。保存に失敗した時は入れたのを取り消し、次の保存では新しい下書きを使う (Mac の編集画面と同じ)。
  @State private var draftSnippet = Snippet(body: "")

  /// 新規の時にサイドバーで選んでいたタグの識別子。タグ名は `@Query` の `tags` から引くため、init ではなく画面に出た時に `tagNames` へ入れる。
  private let initialTagID: UUID?

  /// 入力の初期値をスニペットから決めるため、`@State` の初期値を渡す。新規の時は、サイドバーで選んでいたフォルダ・タグを最初から入れておく。
  init(snippet: Snippet?, initialSidebarItem: SnippetSidebarItem) {
    self.snippet = snippet
    _bodyText = State(initialValue: snippet?.body ?? "")
    _title = State(initialValue: snippet?.title ?? "")
    _keyword = State(initialValue: snippet?.keyword ?? "")
    _language = State(initialValue: snippetLanguagePickerSelection(language: snippet?.language, highlightLanguageNames: snippetHighlightLanguageNames()))
    _color = State(initialValue: snippet?.color)
    _tagNames = State(initialValue: (snippet?.tags ?? []).map(\.name).sorted())
    switch (snippet, initialSidebarItem) {
    case (.some(let snippet), _):
      _folderID = State(initialValue: snippet.folder?.id)
      initialTagID = nil
    case (.none, .library(.folder(let folderID))):
      _folderID = State(initialValue: folderID)
      initialTagID = nil
    case (.none, .library(.tag(let tagID))):
      _folderID = State(initialValue: nil)
      initialTagID = tagID
    case (.none, _):
      _folderID = State(initialValue: nil)
      initialTagID = nil
    }
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Body") {
          SnippetBodyEditor(text: $bodyText, language: language)
            .frame(minHeight: 160)
          // highlight.js の言語を全部 (約 190) 並べるため、メニューではなく一覧の画面で選ばせる。
          Picker("Language", selection: $language) {
            Section {
              Text("Plain Text")
                .tag(String?.none)
            }
            Section {
              ForEach(SnippetLanguage.allCases, id: \.self) { snippetLanguage in
                Text(verbatim: snippetLanguage.displayName)
                  .tag(String?.some(snippetLanguage.rawValue))
              }
            }
            Section {
              ForEach(snippetLanguagePickerOtherLanguageNames(highlightLanguageNames: snippetHighlightLanguageNames()), id: \.self) { languageName in
                Text(verbatim: languageName)
                  .tag(String?.some(languageName))
              }
            }
          }
          .pickerStyle(.navigationLink)
        }
        Section {
          TextField("Title", text: $title, prompt: Text("Uses the first line of the body"))
          TextField("Keyword", text: $keyword, prompt: Text("Keyword"))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
        Section("Folder") {
          Picker("Folder", selection: $folderID) {
            Text("None")
              .tag(UUID?.none)
            ForEach(folders) { folder in
              Text(verbatim: folder.name)
                .tag(UUID?.some(folder.id))
            }
          }
          Button("New Folder", systemImage: "folder.badge.plus") {
            newFolderName = ""
            isCreatingFolder = true
          }
        }
        Section("Tags") {
          ForEach(tagChoices, id: \.self) { tagName in
            Button {
              if tagNames.contains(tagName) {
                tagNames.removeAll { $0 == tagName }
              } else {
                tagNames.append(tagName)
              }
            } label: {
              HStack {
                Text(verbatim: tagName)
                  .foregroundStyle(.primary)
                Spacer()
                if tagNames.contains(tagName) {
                  Image(systemName: "checkmark")
                }
              }
            }
          }
          TextField("Add a Tag", text: $newTagName)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit {
              let tagName = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
              if !tagName.isEmpty && !tagNames.contains(tagName) {
                tagNames.append(tagName)
              }
              newTagName = ""
            }
        }
        Section("Color") {
          SnippetColorPicker(color: $color)
        }
        if let snippet {
          Section {
            SnippetAuthorshipView(snippet: snippet)
          }
        }
      }
      .navigationTitle(snippet == nil ? Text("New Snippet") : Text("Edit Snippet"))
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
      .alert("New Folder", isPresented: $isCreatingFolder) {
        TextField("Folder Name", text: $newFolderName)
        Button("Cancel", role: .cancel) {}
        Button("Add", action: createFolder)
      }
      .alert("Could not save", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
        Button("OK") {}
      } message: {
        Text(verbatim: errorMessage ?? "")
      }
      .onAppear {
        if let initialTagID, let tag = tags.first(where: { $0.id == initialTagID }), !tagNames.contains(tag.name) {
          tagNames.append(tag.name)
        }
      }
    }
  }

  /// タグの選択肢。既存のタグと、この画面で足したまだ無いタグの名前。
  private var tagChoices: [String] {
    let existingTagNames = tags.map(\.name)
    return existingTagNames + tagNames.filter { !existingTagNames.contains($0) }
  }

  /// 入力を検査してスニペットに書き込み、保存して閉じる。検査・保存に失敗したら理由を出し、編集を続けさせる。
  ///
  /// タグの欄に入力したまま Return を押していない名前も付ける (Mac の編集画面と同じ)。
  private func save() {
    let editingSnippet = snippet ?? draftSnippet
    do {
      try applySnippetEdit(
        snippet: editingSnippet,
        body: bodyText,
        title: title,
        keyword: keyword,
        language: language,
        color: color,
        folder: folders.first { $0.id == folderID },
        tagNames: tagNames + [newTagName],
        modelContext: modelContext,
        now: .now
      )
    } catch let validationError as SnippetValidationError {
      errorMessage = validationError.description
      return
    } catch {
      // ストアの読み込みの失敗 (タグの取得など) は書き込みの途中で起き得るため、途中まで書き込んだ変更と新規の挿入を取り消す。
      modelContext.rollback()
      if snippet == nil {
        draftSnippet = Snippet(body: "")
      }
      errorMessage = error.localizedDescription
      return
    }
    // 保存に失敗したら書き込んだ変更と新規の挿入は取り消されている (`saveSnippetChanges(modelContext:)`)。入力は画面の状態に残る。
    if let saveErrorMessage = saveSnippetChanges(modelContext: modelContext) {
      errorMessage = saveErrorMessage
      if snippet == nil {
        draftSnippet = Snippet(body: "")
      }
      return
    }
    Task {
      await snippetEmbeddingController.refreshEmbeddings()
    }
    dismiss()
  }

  /// 入力した名前のフォルダを選ぶ。同じ名前のフォルダがあればそれを使い、無ければ作って保存する。保存に失敗したら理由を出す。
  private func createFolder() {
    let folderName = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !folderName.isEmpty else {
      return
    }
    if let existingFolder = folders.first(where: { $0.name == folderName }) {
      folderID = existingFolder.id
      return
    }
    let newFolder = Folder(name: folderName)
    modelContext.insert(newFolder)
    if let saveErrorMessage = saveSnippetChanges(modelContext: modelContext) {
      errorMessage = saveErrorMessage
      return
    }
    folderID = newFolder.id
  }
}

/// 色の帯の色を選ぶ。色なしと 5 色を並べる (`documents/design/Manager.dc.html` の「色」)。
private struct SnippetColorPicker: View {
  /// 選んでいる色。`nil` は色なし。
  @Binding var color: SnippetColor?

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
      color = snippetColor
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
            .strokeBorder(color == snippetColor ? Color.accentColor : .clear, lineWidth: 2)
        )
    }
    .buttonStyle(.plain)
    .accessibilityLabel(snippetColor.map { Text($0.label) } ?? Text("No Color"))
    .accessibilityAddTraits(color == snippetColor ? .isSelected : [])
  }
}
