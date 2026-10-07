import AppKit
import SwiftData
import SwiftUI
import TanzakuKit

/// 入力が止まってから自動で保存するまでの時間。
///
/// 打鍵の間隔 (1 文字あたりおよそ 100〜200 ミリ秒) より十分長く、打っている途中の内容で保存と意味検索のベクトルの作り直しを繰り返さない長さ。止めてから一覧に反映されるまでの遅れとしては短い。
private let snippetAutosaveDelay: Duration = .seconds(1)

/// スニペットの編集画面 (`documents/design/Manager.dc.html` の右の列)。
///
/// 開いた時に見せるのはキーワードと置き換える内容 (本文) だけにし、タイトル・タグ・フォルダ・色は「追加情報」に畳む (`documents/DIRECTION.md`「決めたこと」)。
/// 入力はこの画面の状態に持ち、入力が止まった時と編集を終えた時に、検査を通った時だけスニペットに書き込む。SwiftData は自動で保存するため、
/// スニペットを直接書き換えると、空の本文や重複したキーワードのまま保存されてしまうため。
struct SnippetEditorView: View {
  /// 編集するスニペット。`nil` は、まだストアに入れていない新規。
  let snippet: Snippet?
  /// スニペットを保存・削除した後に呼び、意味検索のベクトルを作り直させる。
  let onSnippetsChange: () -> Void
  /// 編集を終えた時の保存に失敗した時に、理由を渡して呼ぶ。この画面は消えるため、理由は呼び出し側が出す。
  let onFinishEditingFailure: (String) -> Void
  /// 一覧で選んでいる項目。新規のスニペットを保存したら、そのスニペットを選ぶ。
  @Binding var selection: ManagerDetailSelection?
  @Environment(\.modelContext) private var modelContext
  /// フォルダのメニューに並べるフォルダ。
  @Query(sort: \Folder.name) private var folders: [Folder]
  /// 入力中の本文 (置き換える内容)。
  @State private var bodyText: String
  /// 入力中のタイトル。
  @State private var title: String
  /// 入力中のキーワード。
  @State private var keyword: String
  /// 選んでいる言語 (`Snippet.language` の値)。`nil` はプレーンテキスト。
  @State private var language: String?
  /// 選んでいる色。`nil` は色なし。
  @State private var color: SnippetColor?
  /// 選んでいるフォルダの識別子。サイドバーでフォルダを消しても消したモデルを参照しないよう、モデルではなく識別子で持ち、`folders` から引く。
  @State private var folderID: UUID?
  /// 付けるタグの名前。
  @State private var tagNames: [String]
  /// この編集画面を開いてからユーザーが入力を変えた回数。入力が止まるのを待って保存し直す条件に使う。
  ///
  /// スニペットから入力へ映した変更 (自動のタイトル・タグ、サイドバーで消したタグ) は数えない。数えると、ユーザーが何も変えていないのに画面に残った入力で保存し直し、
  /// 編集画面を開いている間に MCP・同期が変えた本文などを上書きするため。タイトルとタグはスニペットから映すことがあるため、ユーザーが操作する箇所で数える。
  @State private var inputRevision = 0
  /// 最後に保存した時の `inputRevision`。`inputRevision` と同じ間は保存しない (選んだだけで更新日時を変えないため)。
  @State private var savedInputRevision = 0
  /// この編集画面を開いてから 1 回でも保存したか。編集を終えた時に、自動のタイトル・タグを付けるかを決める。
  @State private var hasSavedChanges = false
  /// タグの欄に入力中の、まだタグにしていない名前。
  @State private var newTagName = ""
  /// タグの欄にフォーカスがあるか。フォーカスが外れた時に入力中の名前をタグにする。
  @FocusState private var isTagFieldFocused: Bool
  /// 「追加情報」(タイトル・タグ・フォルダ・色) を開いているか。
  @State private var isAdditionalInfoExpanded: Bool
  /// 保存に失敗した理由。画面にそのまま出す。
  @State private var errorMessage: String?
  /// 新しいフォルダの名前を入力するアラートを出しているか。
  @State private var isCreatingFolder = false
  /// 新しいフォルダの名前の入力。
  @State private var newFolderName = ""
  /// 削除の確認を出しているスニペット。
  @State private var deletingSnippet: Snippet?
  /// 新規作成の下書きのスニペット。検査を通るとストアに入る。ストアへの保存に失敗した時は入れたのを取り消し (`saveManagerChanges(modelContext:)`)、
  /// 次の保存では新しい下書きを使う。取り消したスニペットをもう一度ストアに入れられるかは SwiftData が保証していないため。
  @State private var draftSnippet: Snippet

  /// 編集画面の入力の初期値をスニペットから決めるため、`@State` の初期値を渡す。
  ///
  /// `snippetID` は新規のスニペットに付ける識別子 (`ManagerDetailSelection.newSnippet` の `draftID`)。保存の前後で編集画面を同じ識別子で出し続け、入力中のフォーカスを保つため。
  /// `draftTitle` は新規の時のタイトルの初期値 (ランチャーに入力した言葉)。
  init(
    snippet: Snippet?,
    snippetID: UUID,
    draftTitle: String,
    onSnippetsChange: @escaping () -> Void,
    onFinishEditingFailure: @escaping (String) -> Void,
    selection: Binding<ManagerDetailSelection?>
  ) {
    self.snippet = snippet
    self.onSnippetsChange = onSnippetsChange
    self.onFinishEditingFailure = onFinishEditingFailure
    _selection = selection
    _bodyText = State(initialValue: snippet?.body ?? "")
    _title = State(initialValue: snippet?.title ?? draftTitle)
    _keyword = State(initialValue: snippet?.keyword ?? "")
    _language = State(initialValue: snippetLanguagePickerSelection(language: snippet?.language, highlightLanguageNames: snippetHighlightLanguageNames()))
    _color = State(initialValue: snippet?.color)
    _folderID = State(initialValue: snippet?.folder?.id)
    _tagNames = State(initialValue: (snippet?.tags ?? []).map(\.name).sorted())
    // ランチャーに入力した言葉はタイトルに入るため、入ったことが見えるよう開いておく。それ以外は issue #55 のとおり閉じておく。
    _isAdditionalInfoExpanded = State(initialValue: snippet == nil && !draftTitle.isEmpty)
    _draftSnippet = State(initialValue: makeDraftSnippet(snippetID: snippetID))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if !keyword.isEmpty {
        SnippetGroupPermissionGuide()
          // 高さが足りない時は、案内の文を切り詰める前に置き換える内容の欄を縮める。案内の文には、打った内容を保存も送信もしないことが書いてあるため。
          .layoutPriority(1)
      }
      HStack(spacing: 14) {
        Text("Keyword")
          .foregroundStyle(.secondary)
        TextField("Keyword", text: $keyword)
          .labelsHidden()
          .frame(width: 160)
          .accessibilityIdentifier("snippet-keyword-field")
      }
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 12) {
          Text("Replacement")
            .foregroundStyle(.secondary)
          Picker("Language", selection: $language) {
            Text("Plain Text").tag(String?.none)
            Divider()
            ForEach(SnippetLanguage.allCases, id: \.self) { snippetLanguage in
              Text(verbatim: snippetLanguage.displayName).tag(String?.some(snippetLanguage.rawValue))
            }
            Divider()
            ForEach(snippetLanguagePickerOtherLanguageNames(highlightLanguageNames: snippetHighlightLanguageNames()), id: \.self) { languageName in
              Text(verbatim: languageName).tag(String?.some(languageName))
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
        // 新規作成 (⌘N) は置き換える内容から書き始めるため、開いた時にカーソルを入れる。既存のスニペットを選んだ時は、一覧を ↑↓ で動かし続けられるよう入れない。
        SnippetBodyEditor(text: $bodyText, language: language, focusesOnAppear: snippet == nil)
          .padding(10)
          // 本文の背景はデザインの code の値 (`documents/design/Manager.dc.html` の LIGHT / DARK)。
          .background(appearanceAdaptiveColor(lightHex: 0xF6F7F9, darkHex: 0x19191B), in: RoundedRectangle(cornerRadius: 8))
          .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
      }
      DisclosureGroup(isExpanded: $isAdditionalInfoExpanded) {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
          GridRow {
            fieldLabel(text: Text("Title"))
            TextField("Title", text: titleInput, prompt: Text("Uses the first line of the replacement when empty"))
              .labelsHidden()
              .accessibilityIdentifier("snippet-title-field")
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
        .padding(.top, 8)
      } label: {
        Text("Additional Info")
          .foregroundStyle(.secondary)
          // macOS の DisclosureGroup は三角のクリックでしか開閉しないため、見出しの文字のクリックでも開閉する。
          .contentShape(Rectangle())
          .onTapGesture {
            isAdditionalInfoExpanded.toggle()
          }
          // DisclosureGroup に付けると、中の欄の識別子 (`snippet-title-field` など) がこの識別子に置き換わるため、見出しに付ける。
          .accessibilityIdentifier("snippet-additional-info")
      }
      if let errorMessage {
        Text(verbatim: errorMessage)
          .foregroundStyle(.red)
          .accessibilityIdentifier("snippet-error-message")
      }
      if let snippet {
        HStack(spacing: 16) {
          SnippetHistoryText(snippet: snippet)
          Spacer()
          Button("Delete…", role: .destructive) {
            deletingSnippet = snippet
          }
          .accessibilityIdentifier("snippet-delete-button")
        }
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
    // 前に編集を終えた時の自動のタグ (`generateSnippetMetadata(snippet:userDefaults:modelContext:)`) は、この画面を開き直した後に付くことがある。
    // 入力に足さないと、次の自動保存が開いた時のタグで上書きして消すため、スニペットに付いた名前を入力にも足す。
    // 足すのは、保存していない入力が無い時だけ (`hasUnsavedInput`)。
    .onChange(of: (snippet?.tags ?? []).map(\.name).sorted()) { oldTagNames, newTagNames in
      let removedTagNames = Set(oldTagNames).subtracting(newTagNames)
      tagNames.removeAll { removedTagNames.contains($0) }
      if !hasUnsavedInput {
        tagNames.append(contentsOf: newTagNames.filter { !oldTagNames.contains($0) && !tagNames.contains($0) })
      }
    }
    // 自動のタイトルも同じく開き直した後に付くことがある。保存していない入力が無く、ユーザーがタイトルの入力を変えていなければ入力に映す。
    .onChange(of: snippet?.title) { oldTitle, newTitle in
      // 空の入力はタイトルなし (`nil`) として保存しているため、タイトルなしは空の入力と比べる。
      if !hasUnsavedInput && title == (oldTitle ?? "") {
        title = newTitle ?? ""
      }
    }
    .onChange(of: isTagFieldFocused) {
      if !isTagFieldFocused {
        commitNewTagName()
      }
    }
    .onChange(of: bodyText) {
      inputRevision += 1
    }
    .onChange(of: keyword) {
      inputRevision += 1
    }
    .onChange(of: language) {
      inputRevision += 1
    }
    .onChange(of: color) {
      inputRevision += 1
    }
    .onChange(of: folderID) {
      inputRevision += 1
    }
    .task(id: inputRevision) {
      guard hasUnsavedInput else {
        return
      }
      do {
        try await Task.sleep(for: snippetAutosaveDelay)
      } catch {
        return
      }
      // 入力の途中の失敗は、この画面に出す理由で足りるため、ほかへは伝えない。
      save(tagNames: tagNames, onFailure: { _ in })
    }
    .onDisappear(perform: finishEditing)
    // 入力が止まるのを待つ間にアプリを終了しても、入力を失わないため。
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
      save(tagNames: tagNamesAddingNewTagName(), onFailure: onFinishEditingFailure)
    }
  }

  /// タイトルの欄の入力。ユーザーが書き換えた時だけ `inputRevision` を進める (スニペットから映した変更と区別するため)。
  private var titleInput: Binding<String> {
    Binding(
      get: { title },
      set: { newTitle in
        if title != newTitle {
          title = newTitle
          inputRevision += 1
        }
      }
    )
  }

  /// ユーザーが変えて、まだ保存していない入力があるか。
  ///
  /// ある間は、スニペットに後から付いた自動のタイトル・タグを入力に映さない。言語モデルは保存済みの本文から作るため、本文を書き換えている途中に届いたものは古い本文のものになる。
  /// 映さなければ次の自動保存が入力 (空のタイトル) で上書きし、編集を終えた時に新しい本文から作り直す。
  private var hasUnsavedInput: Bool {
    inputRevision != savedInputRevision
  }

  /// 書き込む先のスニペット。新規の時は下書き。
  private var editingSnippet: Snippet {
    snippet ?? draftSnippet
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

  /// 付けたタグと、タグを足す入力欄。Return を押すか、欄からフォーカスが外れるとタグにする。
  private var tagsField: some View {
    HStack(spacing: 6) {
      ForEach(tagNames, id: \.self) { tagName in
        HStack(spacing: 4) {
          Text(verbatim: tagName)
          Button {
            tagNames.removeAll { $0 == tagName }
            inputRevision += 1
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
        .focused($isTagFieldFocused)
        .onSubmit(commitNewTagName)
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

  /// 付けるタグの名前に、タグの欄に入力中の名前を足したもの。空の名前と、付けてあるタグと同じ名前は足さない。
  private func tagNamesAddingNewTagName() -> [String] {
    let tagName = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
    return tagName.isEmpty || tagNames.contains(tagName) ? tagNames : tagNames + [tagName]
  }

  /// タグの欄に入力中の名前をタグにする。空の名前と、付けてあるタグと同じ名前では入力中の名前を消すだけのため、何度呼んでもタグは 1 つしか増えない。
  private func commitNewTagName() {
    let newTagNames = tagNamesAddingNewTagName()
    if newTagNames != tagNames {
      tagNames = newTagNames
      inputRevision += 1
    }
    newTagName = ""
  }

  /// 入力を検査してスニペットに書き込み、保存する。保存したら `true`。新規のスニペットは保存できたら一覧で選ぶ。
  ///
  /// `tagNames` は付けるタグの名前。編集を終える時は、タグの欄に入力中で Return を押していない名前も足して渡す (`tagNamesAddingNewTagName()`)。
  /// 最後に保存した後に入力を変えていなければ何もしないため、入力を変えずに何度呼んでも保存は 1 回になる。
  /// 検査を通らない入力 (空の置き換える内容・重複したキーワード) は書き込まずに理由を出す。ストアには最後に検査を通った内容が残る。
  /// 理由はこの画面に出し、`onFailure` にも渡す。編集を終えた時はこの画面が消えて理由が見えないため、呼び出し側が出せるようにする。
  @discardableResult
  private func save(tagNames: [String], onFailure: (String) -> Void) -> Bool {
    let editingSnippet = self.editingSnippet
    // 編集中に消されたスニペット (この画面の削除・MCP・同期) には書き込まない。消したスニペットは属性を読めないため、属性を読む前に確かめる。
    if let snippet, !isSnippetInStore(snippet: snippet) {
      return false
    }
    let isNewSnippet = editingSnippet.modelContext == nil
    // 保存に失敗して挿入を取り消した後のスニペットも属性を読めないため、識別子は書き込む前に取っておく。
    let editingSnippetID = editingSnippet.id
    guard hasUnsavedInput || tagNames != self.tagNames else {
      return false
    }
    // 新規で置き換える内容をまだ書いていない間は、キーワードやタイトルを先に入れても検査の理由を出さず、書くのを待つ。
    if isNewSnippet && bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      errorMessage = nil
      return false
    }
    do {
      try applySnippetEdit(
        snippet: editingSnippet,
        body: bodyText,
        title: title,
        keyword: keyword,
        language: language,
        color: color,
        folder: selectedFolder,
        tagNames: tagNames,
        modelContext: modelContext,
        now: .now
      )
      // 保存に失敗したら、書き込んだ変更と新規の挿入を取り消す。残すと、自動保存や別の項目の保存で失敗した変更まで保存されるため。入力は画面の状態に残る。
      if let saveErrorMessage = saveManagerChanges(modelContext: modelContext) {
        errorMessage = saveErrorMessage
        onFailure(saveErrorMessage)
        if isNewSnippet {
          draftSnippet = makeDraftSnippet(snippetID: editingSnippetID)
        }
        return false
      }
      savedInputRevision = inputRevision
      hasSavedChanges = true
      errorMessage = nil
      onSnippetsChange()
      // 一覧でこの下書きを選んでいる間だけ選び直す。編集を終えた時の保存 (別の項目を選んだ後) で、選んだ項目を戻さないため。
      if case .newSnippet(let draftID, _) = selection, draftID == editingSnippetID {
        selection = .snippet(snippetID: editingSnippetID)
      }
      return true
    } catch let validationError as SnippetValidationError {
      errorMessage = validationError.description
      onFailure(validationError.description)
      return false
    } catch {
      // ストアの読み込みの失敗 (タグの取得など) は書き込みの途中で起き得るため、途中まで書き込んだ変更と新規の挿入を取り消す。
      modelContext.rollback()
      if isNewSnippet {
        draftSnippet = makeDraftSnippet(snippetID: editingSnippetID)
      }
      errorMessage = error.localizedDescription
      onFailure(error.localizedDescription)
      return false
    }
  }

  /// 編集を終えた時 (別の項目を選んだ・ウィンドウを閉じた) の処理。入力が止まるのを待っている入力を保存し、この画面で保存したスニペットに自動のタイトル・タグを付ける。
  ///
  /// タイトル・タグを入力の途中ではなくここで作るのは、書きかけの内容から作らないため (`documents/DIRECTION.md`「決めたこと」)。
  /// 言語モデルの応答はこの画面が消えた後に届くため、画面の状態ではなくスニペットに書き込む (`generateSnippetMetadata(snippet:userDefaults:modelContext:)`)。
  private func finishEditing() {
    let editingSnippet = self.editingSnippet
    guard save(tagNames: tagNamesAddingNewTagName(), onFailure: onFinishEditingFailure) || hasSavedChanges, isSnippetInStore(snippet: editingSnippet) else {
      return
    }
    Task { [modelContext, onSnippetsChange] in
      if await generateSnippetMetadata(snippet: editingSnippet, userDefaults: .standard, modelContext: modelContext) {
        onSnippetsChange()
      }
    }
  }

  /// 入力した名前のフォルダを選ぶ。同じ名前のフォルダがあればそれを使い、無ければ作る。作ったフォルダの保存に失敗したら、作るのを取り消して理由を編集の列に出す。
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
    if let saveErrorMessage = saveManagerChanges(modelContext: modelContext) {
      errorMessage = saveErrorMessage
      return
    }
    folderID = newFolder.id
  }
}

/// 新規作成の下書きのスニペットを作る。`snippetID` を識別子にし、保存の前後で一覧の選択と編集画面が同じスニペットを指せるようにする。
private func makeDraftSnippet(snippetID: UUID) -> Snippet {
  let snippet = Snippet(body: "")
  snippet.id = snippetID
  return snippet
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
