import CryptoKit
import Foundation
import SwiftData

/// `Snippet.createdByKind` / `updatedByKind` の、MCP のクライアントが作成・更新したことを表す値 (`documents/data-model.md`「Snippet」)。
public let snippetAuthorKindMCP = "mcp"

/// キーワード展開で打つ文字と入る文字 (キーワードと本文) を表すハッシュ。承認した内容と今の内容が同じかを比べるために使う。
///
/// キーワードと本文の間に NUL を挟み、境目を動かしただけの別の組み合わせ (`ab` + `c` と `a` + `bc`) が同じハッシュにならないようにする。
/// 添付は含めない。MCP のクライアントは添付を変えられず (`update_snippet`)、添付を変えるのは編集画面でユーザーが保存した時だけで、その時は更新した主体が `user` になり承認を読まないため。
public func snippetKeywordExpansionContentHash(snippet: Snippet) -> String {
  SHA256.hash(data: Data(((snippet.keyword ?? "") + "\u{0}" + snippet.body).utf8))
    .map { String(format: "%02x", $0) }
    .joined()
}

/// MCP のクライアントが作成・更新した内容をユーザーがまだ承認しておらず、キーワード展開に使わないスニペットか。
///
/// MCP のクライアントの書き込みが、ユーザーの見ていない文面のまま他のアプリへの入力にならないようにする (#68)。
/// ユーザーが編集画面で保存したスニペットは更新した主体が `user` になり、内容を見たものとして承認待ちにしない。
public func snippetIsAwaitingKeywordExpansionApproval(snippet: Snippet) -> Bool {
  snippet.updatedByKind == snippetAuthorKindMCP && snippet.mcpApprovedContentHash != snippetKeywordExpansionContentHash(snippet: snippet)
}

/// 今のキーワードと本文を承認し、キーワード展開に使えるようにして保存する。
///
/// 承認しても `updatedAt` と更新の主体は変えない。内容を変えたのは MCP のクライアントのままで、編集画面の「MCP 経由で変更」の表示を残すため。
/// 何度呼んでも同じ内容を承認した状態になる。
public func approveSnippetKeywordExpansion(snippet: Snippet, modelContext: ModelContext) throws {
  snippet.mcpApprovedContentHash = snippetKeywordExpansionContentHash(snippet: snippet)
  try modelContext.save()
}
