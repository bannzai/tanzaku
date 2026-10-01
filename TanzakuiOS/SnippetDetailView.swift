import SwiftData
import SwiftUI
import TanzakuKit

/// iPad の詳細の列に出すスニペット。本文を等幅で全部見せ、キーワード・タグ・フォルダ・作成と更新の主体を並べる (`documents/design/Manager.dc.html` の右側)。
///
/// 書き換えは編集画面 (sheet) で行い、検査を通った時だけ保存する (`applySnippetEdit`)。
struct SnippetDetailView: View {
  /// 出すスニペット。
  var snippet: Snippet

  /// 削除と、コピーした時の使った日時の記録に使う。
  @Environment(\.modelContext) private var modelContext
  /// 削除の後に意味検索のベクトルを作り直させる。
  @Environment(SnippetEmbeddingController.self) private var snippetEmbeddingController
  /// 編集画面を出しているもの。
  @State private var snippetEditor: SnippetEditorTarget?
  /// 削除の保存の失敗。
  @State private var errorMessage: String?
  /// 本文のハイライトの配色をライト・ダークで切り替える。
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    Form {
      Section {
        HStack(spacing: 10) {
          SnippetColorBand(snippet: snippet)
            .frame(height: 22)
          Text(verbatim: snippetDisplayTitle(snippet: snippet))
            .font(.headline)
        }
        if let keyword = snippet.keyword {
          LabeledContent("Keyword") {
            Text(verbatim: keyword)
          }
        }
        if let tags = snippet.tags, !tags.isEmpty {
          LabeledContent("Tags") {
            Text(verbatim: tags.map(\.name).sorted().joined(separator: ", "))
          }
        }
        if let folder = snippet.folder {
          LabeledContent("Folder") {
            Text(verbatim: folder.name)
          }
        }
        LabeledContent("Language") {
          // 編集画面の Picker と同じく、Picker に並ばない値はハイライトしないためプレーンテキストと出す。
          if let language = snippetLanguagePickerSelection(language: snippet.language, highlightLanguageNames: snippetHighlightLanguageNames()) {
            Text(verbatim: snippetLanguageDisplayName(language: language))
          } else {
            Text("Plain Text")
          }
        }
      }
      Section("Body") {
        Text(highlightedSnippetBody(body: snippet.body, language: snippet.language, colorScheme: colorScheme))
          .font(.callout.monospaced())
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      Section {
        SnippetAuthorshipView(snippet: snippet)
      }
    }
    .navigationTitle(Text(verbatim: snippetDisplayTitle(snippet: snippet)))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        Button("Copy", systemImage: "doc.on.doc") {
          copySnippetBodyAndRecordUse(snippet: snippet, modelContext: modelContext)
        }
        ShareLink(item: snippet.body)
        Button("Edit", systemImage: "pencil") {
          snippetEditor = SnippetEditorTarget(snippet: snippet, sidebarItem: .library(filter: .all))
        }
        Button("Delete", systemImage: "trash", role: .destructive) {
          modelContext.delete(snippet)
          errorMessage = saveSnippetChanges(modelContext: modelContext)
          if errorMessage == nil {
            Task {
              await snippetEmbeddingController.refreshEmbeddings()
            }
          }
        }
      }
    }
    .sheet(item: $snippetEditor) { snippetEditor in
      SnippetEditorView(snippet: snippetEditor.snippet, initialSidebarItem: snippetEditor.sidebarItem)
    }
    .alert("Could not delete", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
      Button("OK") {}
    } message: {
      Text(verbatim: errorMessage ?? "")
    }
  }
}

/// 作成・更新の日付と主体。MCP クライアントが作った・変えたスニペットはクライアント名を出す (`documents/DIRECTION.md`「決めたこと」)。
struct SnippetAuthorshipView: View {
  /// 出すスニペット。
  var snippet: Snippet

  var body: some View {
    LabeledContent("Created") {
      authorshipText(date: snippet.createdAt, clientName: snippet.createdByKind == "mcp" ? snippet.createdByClientName : nil)
    }
    LabeledContent("Updated") {
      authorshipText(date: snippet.updatedAt, clientName: snippet.updatedByKind == "mcp" ? snippet.updatedByClientName : nil)
    }
  }

  /// 日付と、MCP クライアントの時だけその名前。
  private func authorshipText(date: Date, clientName: String?) -> Text {
    if let clientName {
      Text("\(date.formatted(date: .abbreviated, time: .shortened)) (by \(clientName) via MCP)")
    } else {
      Text(date, format: .dateTime.year().month().day().hour().minute())
    }
  }
}
