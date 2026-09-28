import SwiftData
import SwiftUI
import TanzakuKit
import os

/// スニペットの一覧。タップで本文をコピーし、検索・追加・編集・削除・共有をここから行う。
///
/// iOS ではほかのアプリの入力欄へ貼るのが主な使い方のため、行のタップをコピーにする。編集と削除は行のスワイプと長押しのメニューに置く。
/// iPad では、タップした行を詳細の列にも出す。
struct SnippetListView: View {
  /// 一覧の絞り込み。
  var filter: SnippetLibraryFilter
  /// iPad の詳細の列に出すスニペット。iPhone では `nil`。
  var selectedSnippet: Binding<Snippet?>?

  /// すべてのスニペット。更新日時の新しい順 (`documents/design/Manager.dc.html` の一覧)。
  @Query(sort: \Snippet.updatedAt, order: .reverse) private var snippets: [Snippet]
  /// 保存・削除・検索に使う。
  @Environment(\.modelContext) private var modelContext
  /// 意味検索の埋め込みモデル。
  @Environment(\.snippetTextEmbedder) private var snippetTextEmbedder
  /// 検索欄の入力。
  @State private var searchQuery = ""
  /// 入力で検索した結果。入力が空の時は使わない。
  @State private var searchResult = SnippetSearchResult(keywordMatches: [], semanticMatches: [])
  /// 編集画面を出しているスニペット。
  @State private var editingSnippet: Snippet?
  /// 編集画面が追加か。
  @State private var isEditingNewSnippet = false
  /// 最後にコピーしたスニペット。コピーしたことを知らせる表示に使う。
  @State private var copiedSnippet: Snippet?
  /// コピーした回数。同じ行を続けてタップした時も、表示の時間を測り直して触覚で知らせるため。
  @State private var copyCount = 0
  /// 保存・削除・検索の失敗。
  @State private var errorMessage: String?

  var body: some View {
    List {
      if trimmedSearchQuery.isEmpty {
        ForEach(filteredLibrarySnippets(snippets: snippets, filter: filter)) { snippet in
          snippetRow(snippet: snippet)
        }
      } else {
        if !searchResult.keywordMatches.isEmpty {
          Section("Keyword Matches") {
            ForEach(searchResult.keywordMatches.map(\.snippet)) { snippet in
              snippetRow(snippet: snippet)
            }
          }
        }
        if !searchResult.semanticMatches.isEmpty {
          Section {
            ForEach(searchResult.semanticMatches) { snippet in
              snippetRow(snippet: snippet)
            }
          } header: {
            Text("Similar Meaning")
          } footer: {
            Text("Searched by the meaning of keywords, titles, and bodies")
          }
        }
      }
    }
    .overlay {
      if trimmedSearchQuery.isEmpty, filteredLibrarySnippets(snippets: snippets, filter: filter).isEmpty {
        ContentUnavailableView("No Snippets", systemImage: "rectangle.portrait", description: Text("Tap + to add a snippet"))
      } else if !trimmedSearchQuery.isEmpty, searchResult.keywordMatches.isEmpty, searchResult.semanticMatches.isEmpty {
        ContentUnavailableView.search(text: trimmedSearchQuery)
      }
    }
    .overlay(alignment: .bottom) {
      if let copiedSnippet {
        Label {
          Text("Copied “\(snippetDisplayTitle(snippet: copiedSnippet))”")
        } icon: {
          Image(systemName: "checkmark.circle.fill")
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .padding(.bottom, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task(id: copyCount) {
          // 2 秒はコピーしたスニペットの名前を読み終えられる程度の長さ。キャンセル (続けてコピーした) の時は次のコピーの表示を消さない。
          guard (try? await Task.sleep(for: .seconds(2))) != nil else {
            return
          }
          withAnimation {
            self.copiedSnippet = nil
          }
        }
      }
    }
    .sensoryFeedback(.success, trigger: copyCount)
    .searchable(text: $searchQuery, prompt: Text("Search by keyword or meaning"))
    .onChange(of: searchQuery) {
      search()
    }
    // iPad で検索の入力を残したままサイドバーの絞り込みを変えた時に、新しい絞り込みの中で検索し直す。
    .onChange(of: filter) {
      search()
    }
    .task(id: snippetTextEmbedder?.modelIdentifier) {
      refreshSnippetEmbeddings()
      search()
    }
    // 保存・削除 (この一覧・iPad の詳細の列・開発者メニューのどこからでも) で更新日時か件数が変わった時に、ベクトルと検索の結果を合わせる。
    .onChange(of: snippets.map(\.updatedAt)) {
      refreshSnippetEmbeddings()
      search()
    }
    .navigationTitle(navigationTitle)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("New Snippet", systemImage: "plus") {
          let snippet = Snippet(body: "")
          modelContext.insert(snippet)
          if case .folder(let folder) = filter {
            snippet.folder = folder
          }
          if case .tag(let tag) = filter {
            snippet.tags = [tag]
          }
          isEditingNewSnippet = true
          editingSnippet = snippet
        }
      }
      #if DEBUG
        ToolbarItem(placement: .secondaryAction) {
          DeveloperMenu()
        }
      #endif
    }
    .sheet(
      item: $editingSnippet,
      onDismiss: {
        // 取り消した編集を捨てる。保存した後なら捨てるものは無い。
        modelContext.rollback()
        // 編集画面を出している間に埋め込みモデルの用意が済んだ時は、ベクトルの作り直しを見送っているため、ここで合わせる。
        refreshSnippetEmbeddings()
      }
    ) { snippet in
      SnippetEditorView(snippet: snippet, isNewSnippet: isEditingNewSnippet)
    }
    .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
      Button("OK") {}
    } message: {
      Text(verbatim: errorMessage ?? "")
    }
  }

  /// 一覧の 1 行。タップでコピーし、スワイプと長押しで編集・削除・共有する。
  private func snippetRow(snippet: Snippet) -> some View {
    Button {
      copy(snippet: snippet)
      selectedSnippet?.wrappedValue = snippet
    } label: {
      SnippetRow(snippet: snippet)
    }
    .foregroundStyle(.primary)
    .listRowBackground(selectedSnippet?.wrappedValue?.id == snippet.id ? Color.accentColor.opacity(0.15) : nil)
    .swipeActions(edge: .trailing) {
      Button("Delete", systemImage: "trash", role: .destructive) {
        delete(snippet: snippet)
      }
      Button("Edit", systemImage: "pencil") {
        isEditingNewSnippet = false
        editingSnippet = snippet
      }
      .tint(.accentColor)
    }
    .contextMenu {
      Button("Copy", systemImage: "doc.on.doc") {
        copy(snippet: snippet)
      }
      Button("Edit", systemImage: "pencil") {
        isEditingNewSnippet = false
        editingSnippet = snippet
      }
      ShareLink(item: snippet.body)
      Button("Delete", systemImage: "trash", role: .destructive) {
        delete(snippet: snippet)
      }
    }
  }

  /// 本文をクリップボードに入れ、コピーしたことを知らせる。冪等ではない: 呼ぶたびに知らせる表示と触覚の合図が 1 回起きる。
  private func copy(snippet: Snippet) {
    copySnippetBodyToPasteboard(body: snippet.body)
    withAnimation {
      copiedSnippet = snippet
    }
    copyCount += 1
  }

  /// 前後の空白を除いた検索欄の入力。
  private var trimmedSearchQuery: String {
    searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// 画面の題。絞り込みの名前にする。
  private var navigationTitle: Text {
    switch filter {
    case .allSnippets:
      Text("All Snippets")
    case .addedByAgent:
      Text("Added by AI Agents")
    case .folder(let folder):
      Text(verbatim: folder.name)
    case .tag(let tag):
      Text(verbatim: tag.name)
    case .snippetGroup(let snippetGroup):
      Text(verbatim: snippetGroup.name)
    }
  }

  /// 検索欄の入力で検索し直す。入力が空なら何もしない (一覧を出すため)。
  private func search() {
    guard !trimmedSearchQuery.isEmpty else {
      return
    }
    do {
      searchResult = try searchSnippets(query: searchQuery, modelContext: modelContext, embedder: snippetTextEmbedder, libraryFilter: filter)
    } catch {
      snippetListLogger.error("Failed to search snippets: \(String(describing: error))")
      searchResult = SnippetSearchResult(keywordMatches: [], semanticMatches: [])
    }
  }

  /// 意味検索のベクトルを今のスニペットに合わせる。変わっていないベクトルは作り直さない。
  ///
  /// 保存していない変更がある間 (編集画面を出している間) は作り直さない。ベクトルの保存が、検査を通っていない編集まで一緒に保存するため。
  /// 編集を保存するか取り消すと一覧のスニペットが変わり、`onChange` からもう一度呼ばれる。
  private func refreshSnippetEmbeddings() {
    guard let snippetTextEmbedder, !modelContext.hasChanges else {
      return
    }
    do {
      try updateSnippetEmbeddings(modelContext: modelContext, embedder: snippetTextEmbedder)
      try modelContext.save()
    } catch {
      modelContext.rollback()
      snippetListLogger.error("Failed to update snippet embeddings: \(String(describing: error))")
    }
  }

  /// スニペットを消す。詳細の列に出していれば先に外す (消したモデルを画面が読まないため)。
  private func delete(snippet: Snippet) {
    if selectedSnippet?.wrappedValue?.id == snippet.id {
      selectedSnippet?.wrappedValue = nil
    }
    if copiedSnippet?.id == snippet.id {
      copiedSnippet = nil
    }
    do {
      try deleteSnippets(snippets: [snippet], modelContext: modelContext)
    } catch {
      modelContext.rollback()
      errorMessage = String(describing: error)
    }
    search()
  }
}

/// 一覧のエラーの記録。スニペットの本文は入れない (`.claude/rules/snippet-content-handling.md`)。
private let snippetListLogger = Logger(subsystem: "com.bannzai.tanzaku", category: "SnippetList")

/// 一覧の 1 行の中身。色の帯・名前・更新日・本文の 1 行目・キーワードを並べる (`documents/design/Manager.dc.html` の一覧の行)。
struct SnippetRow: View {
  /// 行のスニペット。
  var snippet: Snippet

  var body: some View {
    HStack(spacing: 10) {
      SnippetColorBand(snippet: snippet)
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline) {
          Text(verbatim: snippetDisplayTitle(snippet: snippet))
            .font(.subheadline.weight(.semibold))
          Spacer(minLength: 8)
          Text(snippet.updatedAt, format: .dateTime.month().day())
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Text(verbatim: snippetBodyFirstLine(body: snippet.body))
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
        if let keyword = snippet.keyword {
          Text(verbatim: keyword)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
      .lineLimit(1)
    }
    .padding(.vertical, 2)
  }
}
