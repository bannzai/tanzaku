import Foundation
import SwiftData

/// `Snippet.createdByKind` / `updatedByKind` の、MCP のクライアントが作成・更新したことを表す値 (`documents/data-model.md`「Snippet」)。
public let snippetAuthorKindMCP = "mcp"

/// MCP のクライアントが作成・更新した内容をユーザーがまだ承認しておらず、キーワード展開に使わないスニペットか。
///
/// MCP のクライアントの書き込みが、ユーザーの見ていない文面のまま他のアプリへの入力にならないようにする (#68)。
/// ユーザーが編集画面で保存したスニペットは更新した主体が `user` になり、内容を見たものとして承認待ちにしない。
public func snippetIsAwaitingKeywordExpansionApproval(snippet: Snippet) -> Bool {
  snippet.updatedByKind == snippetAuthorKindMCP && !snippet.isMCPUpdateApproved
}

/// MCP のクライアントによる最後の作成・更新を承認し、キーワード展開に使えるようにして保存する。
///
/// 承認しても `updatedAt` と更新の主体は変えない。内容を変えたのは MCP のクライアントのままで、編集画面の「MCP 経由で変更」の表示を残すため。
/// 何度呼んでも承認済みのままになる。
public func approveSnippetKeywordExpansion(snippet: Snippet, modelContext: ModelContext) throws {
  snippet.isMCPUpdateApproved = true
  try modelContext.save()
}
