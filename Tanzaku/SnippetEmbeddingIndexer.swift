import Foundation
import SwiftData
import TanzakuKit

/// 意味検索の埋め込みモデルと、ベクトルを作る専用の `ModelContext` をメインスレッドの外に持つ。
///
/// 埋め込みモデルの推論はスニペットの数と本文の長さに比例して時間がかかり、メインスレッドで行うとランチャーと管理ウィンドウの操作が止まるため。
/// 埋め込みモデル (NLContextualEmbedding を捕まえた閉包) は Sendable でなく actor の外へ出せないため、作るのも使うのもこの actor の中だけにする。
@ModelActor
actor SnippetEmbeddingIndexer {
  /// 用意できた埋め込みモデル。用意できるまでは `nil`。
  private var snippetTextEmbedder: SnippetTextEmbedder?

  /// 端末の優先言語の埋め込みモデルを用意し、その `modelIdentifier` を返す。資産が無ければダウンロードを待つ。言語に対応するモデルが無い・資産をダウンロードできない時は `nil` を返す。
  func loadSnippetTextEmbedder(preferredLanguages: [String]) async throws -> String? {
    let language = snippetEmbeddingLanguage(preferredLanguages: preferredLanguages)
    guard try await requestContextualEmbeddingAssets(language: language), let snippetTextEmbedder = try makeContextualSnippetTextEmbedder(language: language) else {
      return nil
    }
    self.snippetTextEmbedder = snippetTextEmbedder
    return snippetTextEmbedder.modelIdentifier
  }

  /// すべてのスニペットのベクトルを今の本文と埋め込みモデルに合わせて保存する。変わっていないベクトルは作り直さないため、何度呼んでも結果は同じになる。埋め込みモデルが無ければ何もしない。
  func updateEmbeddings() throws {
    guard let snippetTextEmbedder else {
      return
    }
    try updateSnippetEmbeddings(modelContext: modelContext, embedder: snippetTextEmbedder)
    try modelContext.save()
  }

  /// 検索の入力のベクトル。埋め込みモデルが無ければ `nil`。
  func queryVector(query: String) throws -> [Float]? {
    try snippetTextEmbedder?.vector(query)
  }
}
