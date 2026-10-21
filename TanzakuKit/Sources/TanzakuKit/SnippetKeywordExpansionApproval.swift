import CryptoKit
import Foundation
import SwiftData

/// `Snippet.createdByKind` / `updatedByKind` の、MCP のクライアントが作成・更新したことを表す値 (`documents/data-model.md`「Snippet」)。
public let snippetAuthorKindMCP = "mcp"

/// キーワード展開で打つ文字と入る文字 (キーワードと本文) を表すハッシュ。承認した内容と今の内容が同じかを比べるために使う。
///
/// キーワードと本文の間に NUL を挟み、境目を動かしただけの別の組み合わせ (`ab` + `c` と `a` + `bc`) が同じハッシュにならないようにする。
/// 添付は含めない。MCP のクライアントは添付を変えられず (`update_snippet`)、添付を変えるのは編集画面でユーザーが保存した時だけのため。
public func snippetKeywordExpansionContentHash(snippet: Snippet) -> String {
  SHA256.hash(data: Data(((snippet.keyword ?? "") + "\u{0}" + snippet.body).utf8))
    .map { String(format: "%02x", $0) }
    .joined()
}

/// MCP のクライアントが承認待ちにした時の `Snippet.mcpApprovedContentHash` の値。どの内容のハッシュとも一致しない。
///
/// `nil` ではなくこの値にするのは、`nil` を「承認を記録する前の版で保存した」の意味に残し、同期で更新した主体が `user` と組み合わさっても承認待ちのままにするため。
/// 空文字にしないのは、CloudKit の同期の往復で空文字が `nil` と区別されて届くかを確かめられていないため。SHA-256 の 16 進の文字列にはならない値にする。
public let snippetMCPUnapprovedContentHash = "mcp-unapproved"

/// MCP のクライアントが作成・更新した内容をユーザーがまだ承認しておらず、キーワード展開に使わないスニペットか。
///
/// MCP のクライアントの書き込みが、ユーザーの見ていない文面のまま他のアプリへの入力にならないようにする (#68)。
/// 承認の記録 (承認・編集画面の保存・MCP の書き込みのどれかで入る) があれば、更新した主体によらず今の内容と比べる。別の端末の書き込みと同期で組み合わさっても、見ていない内容を展開しないため。
/// 記録が無い (`nil`) のは承認を記録する前の版で保存したスニペットで、更新した主体が MCP の時だけ承認待ちにする。
public func snippetIsAwaitingKeywordExpansionApproval(snippet: Snippet) -> Bool {
  guard let mcpApprovedContentHash = snippet.mcpApprovedContentHash else {
    return snippet.updatedByKind == snippetAuthorKindMCP
  }
  return mcpApprovedContentHash != snippetKeywordExpansionContentHash(snippet: snippet)
}

/// 今のキーワードと本文を承認し、キーワード展開に使えるようにして保存する。
///
/// 承認しても `updatedAt` と更新の主体は変えない。内容を変えたのは MCP のクライアントのままで、編集画面の「MCP 経由で変更」の表示を残すため。
/// 何度呼んでも同じ内容を承認した状態になる。
public func approveSnippetKeywordExpansion(snippet: Snippet, modelContext: ModelContext) throws {
  snippet.mcpApprovedContentHash = snippetKeywordExpansionContentHash(snippet: snippet)
  try modelContext.save()
}
