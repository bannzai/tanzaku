import Foundation
import SwiftData
import Testing

@testable import TanzakuKit

/// 使った日時の記録 (`recordSnippetUse`) と、最近使ったスニペットの並べ方 (`recentlyUsedSnippets`) を確かめる。
struct SnippetUseTests {
  /// スニペットを置くインメモリのストア。
  private let modelContext: ModelContext

  /// テストごとに空のインメモリのストアを作る。
  init() throws {
    modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
  }

  /// 本文と更新日時を持つスニペットをストアに入れて保存する。
  private func insertSnippet(body: String, updatedAt: Date = Date(timeIntervalSince1970: 0)) throws -> Snippet {
    let snippet = Snippet(body: body)
    snippet.updatedAt = updatedAt
    modelContext.insert(snippet)
    try modelContext.save()
    return snippet
  }

  @Test("使った日時を保存し、更新日時・更新の主体・意味検索のベクトルの元のテキストは変えない")
  func recordSnippetUseKeepsUpdateAttributes() throws {
    let updatedAt = Date(timeIntervalSince1970: 100)
    let snippet = try insertSnippet(body: "echo dummy", updatedAt: updatedAt)
    snippet.updatedByKind = "mcp"
    snippet.updatedByClientName = "dummy-client"
    try modelContext.save()
    let sourceHash = snippetEmbeddingSourceHash(sourceText: snippetEmbeddingSourceText(snippet: snippet))
    let usedAt = Date(timeIntervalSince1970: 200)

    try recordSnippetUse(snippet: snippet, usedAt: usedAt, modelContext: modelContext)

    #expect(!modelContext.hasChanges)
    #expect(snippet.lastUsedAt == usedAt)
    #expect(snippet.updatedAt == updatedAt)
    #expect(snippet.updatedByKind == "mcp")
    #expect(snippet.updatedByClientName == "dummy-client")
    #expect(snippetEmbeddingSourceHash(sourceText: snippetEmbeddingSourceText(snippet: snippet)) == sourceHash)
  }

  @Test("同じ日時で何度記録しても使った日時は同じになる")
  func recordSnippetUseIsIdempotent() throws {
    let snippet = try insertSnippet(body: "echo dummy")
    let usedAt = Date(timeIntervalSince1970: 200)

    try recordSnippetUse(snippet: snippet, usedAt: usedAt, modelContext: modelContext)
    try recordSnippetUse(snippet: snippet, usedAt: usedAt, modelContext: modelContext)

    #expect(snippet.lastUsedAt == usedAt)
    #expect(try recentlyUsedSnippets(modelContext: modelContext).map(\.id) == [snippet.id])
  }

  @Test("使ったことのあるスニペットだけを、更新日時ではなく使った日時の新しい順に返す")
  func recentlyUsedSnippetsAreSortedByLastUsedAt() throws {
    let olderUsedSnippet = try insertSnippet(body: "echo dummy older", updatedAt: Date(timeIntervalSince1970: 300))
    let newerUsedSnippet = try insertSnippet(body: "echo dummy newer", updatedAt: Date(timeIntervalSince1970: 100))
    _ = try insertSnippet(body: "echo dummy unused", updatedAt: Date(timeIntervalSince1970: 400))

    try recordSnippetUse(snippet: olderUsedSnippet, usedAt: Date(timeIntervalSince1970: 1_000), modelContext: modelContext)
    try recordSnippetUse(snippet: newerUsedSnippet, usedAt: Date(timeIntervalSince1970: 2_000), modelContext: modelContext)

    #expect(try recentlyUsedSnippets(modelContext: modelContext).map(\.id) == [newerUsedSnippet.id, olderUsedSnippet.id])
  }

  @Test("使い直したスニペットは先頭に移る")
  func reusedSnippetMovesToFront() throws {
    let firstSnippet = try insertSnippet(body: "echo dummy first")
    let secondSnippet = try insertSnippet(body: "echo dummy second")

    try recordSnippetUse(snippet: firstSnippet, usedAt: Date(timeIntervalSince1970: 1_000), modelContext: modelContext)
    try recordSnippetUse(snippet: secondSnippet, usedAt: Date(timeIntervalSince1970: 2_000), modelContext: modelContext)
    try recordSnippetUse(snippet: firstSnippet, usedAt: Date(timeIntervalSince1970: 3_000), modelContext: modelContext)

    #expect(try recentlyUsedSnippets(modelContext: modelContext).map(\.id) == [firstSnippet.id, secondSnippet.id])
  }

  @Test("使ったことのあるスニペットが上限より多い時は、新しいものから上限の件数だけ返す")
  func recentlyUsedSnippetsAreLimited() throws {
    let snippets = try (0..<(recentlyUsedSnippetLimit + 2)).map { index in
      let snippet = try insertSnippet(body: "echo dummy \(index)")
      try recordSnippetUse(snippet: snippet, usedAt: Date(timeIntervalSince1970: TimeInterval(1_000 + index)), modelContext: modelContext)
      return snippet
    }

    #expect(recentlyUsedSnippetLimit == 10)
    #expect(try recentlyUsedSnippets(modelContext: modelContext).map(\.id) == snippets.reversed().prefix(recentlyUsedSnippetLimit).map(\.id))
  }

  @Test("使ったことのあるスニペットが無ければ空を返す")
  func recentlyUsedSnippetsAreEmptyWithoutUse() throws {
    _ = try insertSnippet(body: "echo dummy")

    #expect(try recentlyUsedSnippets(modelContext: modelContext).isEmpty)
  }
}
