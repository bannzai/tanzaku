import SwiftData
import SwiftUI
import TanzakuKit

/// iPad の詳細の列に出すスニペット。本文を等幅で全部見せ、キーワード・タグ・フォルダ・作成と更新の主体を並べる (`documents/design/Manager.dc.html` の右側)。
///
/// 書き換えは編集画面 (sheet) で行う。詳細の列で直接書き換えると、検査を通る前の値が一覧にも出るため。
struct SnippetDetailView: View {
  /// 出すスニペット。
  var snippet: Snippet
  /// スニペットを消す前に呼ぶ。詳細の列から外し、消したモデルを画面が読まないようにするため。
  var onDelete: () -> Void

  /// 削除に使う。
  @Environment(\.modelContext) private var modelContext
  /// 編集画面を出しているか。
  @State private var isEditing = false
  /// 削除の失敗。
  @State private var errorMessage: String?

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
          if let language = snippet.language.flatMap(SnippetLanguage.init(rawValue:)) {
            Text(verbatim: language.displayName)
          } else {
            Text("Plain Text")
          }
        }
      }
      Section("Body") {
        Text(verbatim: snippet.body)
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
          copySnippetBodyToPasteboard(body: snippet.body)
        }
        ShareLink(item: snippet.body)
        Button("Edit", systemImage: "pencil") {
          isEditing = true
        }
        Button("Delete", systemImage: "trash", role: .destructive) {
          onDelete()
          do {
            try deleteSnippets(snippets: [snippet], modelContext: modelContext)
          } catch {
            modelContext.rollback()
            errorMessage = String(describing: error)
          }
        }
      }
    }
    .sheet(
      isPresented: $isEditing,
      onDismiss: {
        // 取り消した編集を捨てる。保存した後なら捨てるものは無い。
        modelContext.rollback()
      }
    ) {
      SnippetEditorView(snippet: snippet, isNewSnippet: false)
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
      authorshipText(date: snippet.createdAt, clientName: snippet.createdByKind == snippetAuthorMCPKind ? snippet.createdByClientName : nil)
    }
    LabeledContent("Updated") {
      authorshipText(date: snippet.updatedAt, clientName: snippet.updatedByKind == snippetAuthorMCPKind ? snippet.updatedByClientName : nil)
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
