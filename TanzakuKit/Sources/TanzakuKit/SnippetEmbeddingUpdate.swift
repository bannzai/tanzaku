import CryptoKit
import Foundation
import SwiftData

/// 意味検索のベクトルの元にするテキスト。ランチャーの意味検索の欄は「キーワード・タイトル・本文の意味から探しました」と表示するため (`documents/design/Main.dc.html`)、この 3 つをつなげる。
func snippetEmbeddingSourceText(snippet: Snippet) -> String {
  [snippet.keyword, snippet.title, snippet.body].compactMap { $0 }.joined(separator: "\n")
}

/// ベクトルの元にしたテキストのハッシュ (SHA-256 の 16 進表記)。本文を復元できない値にするため、テキストそのものではなくハッシュを持つ (`.claude/rules/snippet-content-handling.md`)。
func snippetEmbeddingSourceHash(sourceText: String) -> String {
  SHA256.hash(data: Data(sourceText.utf8)).map { String(format: "%02x", $0) }.joined()
}

/// ベクトルを長さ 1 にそろえる。内積だけでコサイン類似度を求められるようにするため。長さが 0 のベクトルはそのまま返す。
func l2NormalizedVector(vector: [Float]) -> [Float] {
  let length = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
  guard length > 0 else {
    return vector
  }
  return vector.map { $0 / length }
}

/// `SnippetEmbedding.vector` に入れるバイト列。
func snippetEmbeddingVectorData(vector: [Float]) -> Data {
  vector.withUnsafeBufferPointer { Data(buffer: $0) }
}

/// `SnippetEmbedding.vector` のバイト列から `Float` の配列を読む。`Data` の先頭が `Float` の境界にそろっている保証が無いため、コピーして読む。
func snippetEmbeddingVector(data: Data) -> [Float] {
  [Float](unsafeUninitializedCapacity: data.count / MemoryLayout<Float>.stride) { buffer, initializedCount in
    initializedCount = data.copyBytes(to: buffer) / MemoryLayout<Float>.stride
  }
}

/// すべてのスニペットの意味検索のベクトルを、今の本文と埋め込みモデルに合わせる。
///
/// ベクトルが無いスニペットには作り、`modelIdentifier` か `sourceHash` が一致しないベクトルは作り直し、消えたスニペットのベクトルは消す。
/// 一致しているベクトルは作り直さないため、何度呼んでも結果は同じになる。スニペットの追加・更新の後と、埋め込みモデルの資産のダウンロードが済んだ後に呼ぶ。保存は呼び出し側で行う。
public func updateSnippetEmbeddings(modelContext: ModelContext, embedder: SnippetTextEmbedder) throws {
  let snippets = try modelContext.fetch(FetchDescriptor<Snippet>())
  let embeddingsBySnippetID = Dictionary(grouping: try modelContext.fetch(FetchDescriptor<SnippetEmbedding>()), by: \.snippetID)
  let snippetIDs = Set(snippets.map(\.id))
  for (snippetID, embeddings) in embeddingsBySnippetID where !snippetIDs.contains(snippetID) {
    for embedding in embeddings {
      modelContext.delete(embedding)
    }
  }
  for snippet in snippets {
    let sourceText = snippetEmbeddingSourceText(snippet: snippet)
    let sourceHash = snippetEmbeddingSourceHash(sourceText: sourceText)
    let embeddings = embeddingsBySnippetID[snippet.id] ?? []
    if embeddings.count == 1, embeddings[0].modelIdentifier == embedder.modelIdentifier, embeddings[0].sourceHash == sourceHash {
      continue
    }
    for embedding in embeddings {
      modelContext.delete(embedding)
    }
    modelContext.insert(
      SnippetEmbedding(
        snippetID: snippet.id,
        modelIdentifier: embedder.modelIdentifier,
        sourceHash: sourceHash,
        vector: snippetEmbeddingVectorData(vector: l2NormalizedVector(vector: try embedder.vector(sourceText)))
      )
    )
  }
}
