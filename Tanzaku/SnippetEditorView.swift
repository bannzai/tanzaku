import AppKit
import SwiftData
import SwiftUI
import TanzakuKit

/// スニペットの編集画面 (`documents/design/Manager.dc.html` の右の列)。
///
/// 入力はこの画面の状態に持ち、「保存」で検査を通った時だけスニペットに書き込む。SwiftData は自動で保存するため、
/// スニペットを直接書き換えると、空の本文や重複したキーワードのまま保存されてしまうため。
struct SnippetEditorView: View {
  /// 編集するスニペット。`nil` は新規。
  let snippet: Snippet?
  /// スニペットを保存・削除した後に呼び、意味検索のベクトルを作り直させる。
  let onSnippetsChange: () -> Void
  /// 一覧で選んでいる項目。新規のスニペットを保存したら、そのスニペットを選ぶ。
  @Binding var selection: ManagerDetailSelection?
  @Environment(\.modelContext) private var modelContext
  /// フォルダのメニューに並べるフォルダ。
  @Query(sort: \Folder.name) private var folders: [Folder]
  /// 入力中の本文。
  @State private var bodyText: String
  /// 入力中のタイトル。
  @State private var title: String
  /// 入力中のキーワード。
  @State private var keyword: String
  /// 選んでいる言語。`nil` はプレーンテキスト。
  @State private var language: SnippetLanguage?
  /// 選んでいる色。`nil` は色なし。
  @State private var color: SnippetColor?
  /// 選んでいるフォルダの識別子。サイドバーでフォルダを消しても消したモデルを参照しないよう、モデルではなく識別子で持ち、`folders` から引く。
  @State private var folderID: UUID?
  /// 付けるタグの名前。
  @State private var tagNames: [String]
  /// タグの欄に入力中の、まだタグにしていない名前。
  @State private var newTagName = ""
  /// 保存に失敗した理由。画面にそのまま出す。
  @State private var errorMessage: String?
  /// 新しいフォルダの名前を入力するアラートを出しているか。
  @State private var isCreatingFolder = false
  /// 新しいフォルダの名前の入力。
  @State private var newFolderName = ""
  /// 削除の確認を出しているスニペット。
  @State private var deletingSnippet: Snippet?
  /// 新規作成の下書きのスニペット。検査を通るとストアに入る。ストアへの保存に失敗した後の再試行でも同じスニペットを使い、
  /// 失敗した時に入れたスニペットと別のスニペットを作って、キーワードの重複やレコードの重複にしないため。
  @State private var draftSnippet = Snippet(body: "")

  /// 編集画面の入力の初期値をスニペットから決めるため、`@State` の初期値を渡す。`draftTitle` は新規の時のタイトルの初期値 (ランチャーに入力した言葉)。
  init(snippet: Snippet?, draftTitle: String, onSnippetsChange: @escaping () -> Void, selection: Binding<ManagerDetailSelection?>) {
    self.snippet = snippet
    self.onSnippetsChange = onSnippetsChange
    _selection = selection
    _bodyText = State(initialValue: snippet?.body ?? "")
    _title = State(initialValue: snippet?.title ?? draftTitle)
    _keyword = State(initialValue: snippet?.keyword ?? "")
    _language = State(initialValue: snippet?.language.flatMap(SnippetLanguage.init(rawValue:)))
    _color = State(initialValue: snippet?.color)
    _folderID = State(initialValue: snippet?.folder?.id)
    _tagNames = State(initialValue: (snippet?.tags ?? []).map(\.name).sorted())
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
        GridRow {
          fieldLabel(text: Text("Title"))
          TextField("Title", text: $title, prompt: Text("Uses the first line of the body when empty"))
            .labelsHidden()
            .accessibilityIdentifier("snippet-title-field")
        }
        GridRow {
          fieldLabel(text: Text("Keyword"))
          TextField("Keyword", text: $keyword)
            .labelsHidden()
            .frame(width: 160)
            .accessibilityIdentifier("snippet-keyword-field")
        }
        GridRow {
          fieldLabel(text: Text("Tags"))
          tagsField
        }
        GridRow {
          fieldLabel(text: Text("Folder"))
          folderMenu
        }
        GridRow {
          fieldLabel(text: Text("Color"))
          colorPicker
        }
      }
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 12) {
          Text("Body")
            .foregroundStyle(.secondary)
          Picker("Language", selection: $language) {
            Text("Plain Text").tag(SnippetLanguage?.none)
            Divider()
            ForEach(SnippetLanguage.allCases, id: \.self) { language in
              Text(verbatim: language.displayName).tag(SnippetLanguage?.some(language))
            }
          }
          .labelsHidden()
          .fixedSize()
          Spacer()
          Button("Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(bodyText, forType: .string)
          }
        }
        TextEditor(text: $bodyText)
          .font(.system(size: 13, design: .monospaced))
          .scrollContentBackground(.hidden)
          .padding(10)
          // 本文の背景はデザインの code の値 (`documents/design/Manager.dc.html` の LIGHT / DARK)。
          .background(appearanceAdaptiveColor(lightHex: 0xF6F7F9, darkHex: 0x19191B), in: RoundedRectangle(cornerRadius: 8))
          .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
          .accessibilityIdentifier("snippet-body-editor")
      }
      if let errorMessage {
        Text(verbatim: errorMessage)
          .foregroundStyle(.red)
          .accessibilityIdentifier("snippet-error-message")
      }
      HStack(spacing: 16) {
        if let snippet {
          SnippetHistoryText(snippet: snippet)
        }
        Spacer()
        if let snippet {
          Button("Delete…", role: .destructive) {
            deletingSnippet = snippet
          }
        }
        Button("Save", action: save)
          .keyboardShortcut("s")
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("snippet-save-button")
      }
    }
    .padding(.horizontal, 32)
    .padding(.vertical, 24)
    .alert("New Folder", isPresented: $isCreatingFolder) {
      TextField("Folder Name", text: $newFolderName)
      Button("Create", action: createFolder)
      Button("Cancel", role: .cancel) {}
    }
    .snippetDeleteConfirmation(deletingSnippet: $deletingSnippet, onSnippetsChange: onSnippetsChange, selection: $selection)
    // 編集中にサイドバーでタグを消すと、スニペットからそのタグが外れる。入力に残したまま保存すると同じ名前のタグを作り直してしまうため、入力からも外す。
    // 入力で足したばかりのタグはスニペットにまだ付いていないため、スニペットから外れた名前だけを外す。
    .onChange(of: (snippet?.tags ?? []).map(\.name).sorted()) { oldTagNames, newTagNames in
      let removedTagNames = Set(oldTagNames).subtracting(newTagNames)
      tagNames.removeAll { removedTagNames.contains($0) }
    }
  }

  /// 選んでいるフォルダ。消されたフォルダは `folders` に無いため「なし」になる。
  private var selectedFolder: Folder? {
    folders.first { $0.id == folderID }
  }

  /// 入力欄の左に置く項目名。デザインと同じく右にそろえる。
  private func fieldLabel(text: Text) -> some View {
    text
      .foregroundStyle(.secondary)
      .gridColumnAlignment(.trailing)
  }

  /// 付けたタグと、タグを足す入力欄。Return でタグにする。
  private var tagsField: some View {
    HStack(spacing: 6) {
      ForEach(tagNames, id: \.self) { tagName in
        HStack(spacing: 4) {
          Text(verbatim: tagName)
          Button {
            tagNames.removeAll { $0 == tagName }
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 8, weight: .bold))
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text("Remove Tag"))
        }
        .font(.caption)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
      }
      TextField("Add Tag", text: $newTagName)
        .textFieldStyle(.plain)
        .onSubmit {
          let tagName = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
          if !tagName.isEmpty && !tagNames.contains(tagName) {
            tagNames.append(tagName)
          }
          newTagName = ""
        }
        .accessibilityIdentifier("snippet-tag-field")
    }
    .padding(.horizontal, 6)
    .frame(minHeight: 24)
    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
  }

  /// フォルダを選ぶメニュー。新しいフォルダもここから作る。
  private var folderMenu: some View {
    Menu {
      Button("None") {
        folderID = nil
      }
      if !folders.isEmpty {
        Divider()
        ForEach(folders) { folder in
          Button {
            folderID = folder.id
          } label: {
            Text(verbatim: folder.name)
          }
        }
      }
      Divider()
      Button("New Folder…") {
        newFolderName = ""
        isCreatingFolder = true
      }
    } label: {
      if let folder = selectedFolder {
        Text(verbatim: folder.name)
      } else {
        Text("None")
      }
    }
    .fixedSize()
  }

  /// 色を選ぶボタン。選んでいる色をもう一度押すと色なしにする (色は任意のため)。
  private var colorPicker: some View {
    HStack(spacing: 10) {
      ForEach(SnippetColor.allCases, id: \.self) { snippetColor in
        Button {
          color = color == snippetColor ? nil : snippetColor
        } label: {
          RoundedRectangle(cornerRadius: 2)
            .fill(snippetBandColor(snippetColor: snippetColor))
            .frame(width: 12, height: 20)
            .padding(3)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(color == snippetColor ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(snippetColor.label))
        .accessibilityAddTraits(color == snippetColor ? .isSelected : [])
      }
      if let color {
        Text(color.label)
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        Text("None")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  /// 入力を検査してスニペットに書き込み、保存する。新規のスニペットは保存できたら一覧で選ぶ。
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
        folder: selectedFolder,
        tagNames: tagNames + [newTagName],
        modelContext: modelContext,
        now: .now
      )
      try modelContext.save()
      onSnippetsChange()
      errorMessage = nil
      if snippet == nil {
        selection = .snippet(snippetID: editingSnippet.id)
      } else {
        tagNames = (editingSnippet.tags ?? []).map(\.name).sorted()
        newTagName = ""
      }
    } catch let validationError as SnippetValidationError {
      errorMessage = validationError.description
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  /// 入力した名前のフォルダを選ぶ。同じ名前のフォルダがあればそれを使い、無ければ作る。
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
    try? modelContext.save()
    folderID = newFolder.id
  }
}

/// スニペットの作成・更新の日時と主体。主体が MCP クライアントの時だけクライアント名を添える (`documents/design/Manager.dc.html`)。
private struct SnippetHistoryText: View {
  let snippet: Snippet

  var body: some View {
    HStack(spacing: 16) {
      if snippet.createdByKind == "mcp" {
        Text("Created \(snippet.createdAt, format: .dateTime.month().day()) (added by \(snippet.createdByClientName ?? "") via MCP)")
      } else {
        Text("Created \(snippet.createdAt, format: .dateTime.month().day())")
      }
      if snippet.updatedByKind == "mcp" {
        Text("Updated \(snippet.updatedAt, format: .dateTime.month().day()) (changed by \(snippet.updatedByClientName ?? "") via MCP)")
      } else {
        Text("Updated \(snippet.updatedAt, format: .dateTime.month().day())")
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
  }
}
