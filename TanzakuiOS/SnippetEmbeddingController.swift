import Foundation
import Observation
import SwiftData
import TanzakuKit
import os

/// iOS アプリの意味検索の埋め込みモデルとベクトルの作り直しを受け持ち、一覧の検索に変化を伝える。
///
/// 推論とベクトルの保存は Mac と同じ `SnippetEmbeddingIndexer` (メインスレッドの外の actor) で行う。一覧はこれの `revision` を見て、ベクトルを作り直した時に検索し直す。
@Observable
final class SnippetEmbeddingController {
  /// 埋め込みモデルとベクトルの保存を受け持つ actor。
  private let snippetEmbeddingIndexer: SnippetEmbeddingIndexer
  /// 用意できた埋め込みモデルの識別子。用意できるまで・用意できなかった時は `nil` で、その間は意味検索なしで検索する。
  private(set) var modelIdentifier: String?
  /// ベクトルを作り直した回数。値そのものに意味は無く、変わったことだけを一覧が使う。
  private(set) var revision = 0
  /// 埋め込みモデルとベクトルの失敗の記録。スニペットの本文は入れない (`.claude/rules/snippet-content-handling.md`)。
  private let logger = Logger(subsystem: "com.bannzai.tanzaku", category: "SnippetEmbedding")

  /// ストアと同じ `ModelContainer` からベクトルを作る actor を作る。
  init(modelContainer: ModelContainer) {
    snippetEmbeddingIndexer = SnippetEmbeddingIndexer(modelContainer: modelContainer)
  }

  /// 端末の優先言語の埋め込みモデルを用意し、用意できたらベクトルを作る。資産が無ければダウンロードを待つ。アプリの起動時に 1 回呼ぶ。
  func loadEmbeddingModel() async {
    do {
      modelIdentifier = try await snippetEmbeddingIndexer.loadSnippetTextEmbedder(preferredLanguages: Locale.preferredLanguages)
    } catch {
      logger.error("Failed to load the embedding model: \(String(describing: error), privacy: .public)")
    }
    await refreshEmbeddings()
  }

  /// ベクトルを保存済みのスニペットに合わせる。スニペットを保存・削除した後に呼ぶ。変わっていないベクトルは作り直さないため、何度呼んでも結果は同じになる。
  func refreshEmbeddings() async {
    guard modelIdentifier != nil else {
      return
    }
    do {
      try await snippetEmbeddingIndexer.updateEmbeddings()
      revision += 1
    } catch {
      logger.error("Failed to update snippet embeddings: \(String(describing: error))")
    }
  }

  /// 検索の入力のベクトルを actor で作り、それを返す埋め込みモデルを返す。`filteredSnippets` の意味検索に渡すため。
  ///
  /// 埋め込みモデルが無い時・ベクトルを作れなかった時・取り消された時は `nil` を返し、呼び出し側は意味検索なしで検索する。
  func queryEmbedder(query: String) async -> SnippetTextEmbedder? {
    guard let modelIdentifier else {
      return nil
    }
    do {
      guard let queryVector = try await snippetEmbeddingIndexer.queryVector(query: query) else {
        return nil
      }
      return SnippetTextEmbedder(modelIdentifier: modelIdentifier) { _ in queryVector }
    } catch is CancellationError {
      return nil
    } catch {
      logger.error("Failed to embed the query: \(String(describing: error))")
      return nil
    }
  }
}
