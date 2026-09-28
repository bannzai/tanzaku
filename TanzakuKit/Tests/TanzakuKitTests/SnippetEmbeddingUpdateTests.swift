import Foundation
import SwiftData
import Testing

@testable import TanzakuKit

/// `updateSnippetEmbeddings(modelContext:embedder:)` がベクトルを作る・作り直す・消す条件を、埋め込みモデルの資産を使わない偽の埋め込みで確かめる。
struct SnippetEmbeddingUpdateTests {
  /// 文字数だけからベクトルを作る偽の埋め込み。
  private func characterCountEmbedder(modelIdentifier: String) -> SnippetTextEmbedder {
    SnippetTextEmbedder(modelIdentifier: modelIdentifier) { text in
      [Float(text.count), 1]
    }
  }

  @Test("ベクトルが無いスニペットに作る")
  func createsMissingEmbedding() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let snippet = Snippet(body: "echo dummy")
    modelContext.insert(snippet)

    try updateSnippetEmbeddings(modelContext: modelContext, embedder: characterCountEmbedder(modelIdentifier: "dummy-model"))

    let embeddings = try modelContext.fetch(FetchDescriptor<SnippetEmbedding>())
    #expect(embeddings.map(\.snippetID) == [snippet.id])
    #expect(embeddings.map(\.modelIdentifier) == ["dummy-model"])
    #expect(embeddings.map(\.sourceHash) == [snippetEmbeddingSourceHash(sourceText: "echo dummy")])
  }

  @Test("本文を変えると sourceHash が変わり、ベクトルを作り直す")
  func rebuildsEmbeddingWhenBodyChanges() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let snippet = Snippet(body: "echo dummy")
    modelContext.insert(snippet)
    let embedder = characterCountEmbedder(modelIdentifier: "dummy-model")
    try updateSnippetEmbeddings(modelContext: modelContext, embedder: embedder)
    try modelContext.save()
    let embeddingBeforeUpdate = try #require(try modelContext.fetch(FetchDescriptor<SnippetEmbedding>()).first)
    let sourceHashBeforeUpdate = embeddingBeforeUpdate.sourceHash
    let vectorBeforeUpdate = embeddingBeforeUpdate.vector

    snippet.body = "echo dummy-updated"
    try updateSnippetEmbeddings(modelContext: modelContext, embedder: embedder)
    try modelContext.save()

    let embeddingsAfterUpdate = try modelContext.fetch(FetchDescriptor<SnippetEmbedding>())
    #expect(embeddingsAfterUpdate.count == 1)
    #expect(embeddingsAfterUpdate.map(\.sourceHash) != [sourceHashBeforeUpdate])
    #expect(embeddingsAfterUpdate.map(\.sourceHash) == [snippetEmbeddingSourceHash(sourceText: "echo dummy-updated")])
    #expect(embeddingsAfterUpdate.map(\.vector) != [vectorBeforeUpdate])
  }

  @Test("キーワード・タイトルを変えてもベクトルを作り直す")
  func rebuildsEmbeddingWhenKeywordOrTitleChanges() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let snippet = Snippet(body: "echo dummy")
    modelContext.insert(snippet)
    let embedder = characterCountEmbedder(modelIdentifier: "dummy-model")
    try updateSnippetEmbeddings(modelContext: modelContext, embedder: embedder)

    snippet.keyword = ";dummy"
    snippet.title = "ダミー"
    try updateSnippetEmbeddings(modelContext: modelContext, embedder: embedder)

    #expect(
      try modelContext.fetch(FetchDescriptor<SnippetEmbedding>()).map(\.sourceHash) == [
        snippetEmbeddingSourceHash(sourceText: ";dummy\nダミー\necho dummy")
      ]
    )
  }

  @Test("埋め込みモデルが変わるとベクトルを作り直す")
  func rebuildsEmbeddingWhenModelChanges() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    modelContext.insert(Snippet(body: "echo dummy"))
    try updateSnippetEmbeddings(modelContext: modelContext, embedder: characterCountEmbedder(modelIdentifier: "dummy-model-1"))

    try updateSnippetEmbeddings(modelContext: modelContext, embedder: characterCountEmbedder(modelIdentifier: "dummy-model-2"))

    #expect(try modelContext.fetch(FetchDescriptor<SnippetEmbedding>()).map(\.modelIdentifier) == ["dummy-model-2"])
  }

  @Test("本文もモデルも変わらなければ作り直さない")
  func keepsUpToDateEmbedding() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    modelContext.insert(Snippet(body: "echo dummy"))
    try updateSnippetEmbeddings(modelContext: modelContext, embedder: characterCountEmbedder(modelIdentifier: "dummy-model"))
    try modelContext.save()
    let embeddingIDsBeforeUpdate = try modelContext.fetch(FetchDescriptor<SnippetEmbedding>()).map(\.persistentModelID)

    var embedderCallCount = 0
    try updateSnippetEmbeddings(
      modelContext: modelContext,
      embedder: SnippetTextEmbedder(modelIdentifier: "dummy-model") { _ in
        embedderCallCount += 1
        return [0, 1]
      }
    )

    #expect(embedderCallCount == 0)
    #expect(try modelContext.fetch(FetchDescriptor<SnippetEmbedding>()).map(\.persistentModelID) == embeddingIDsBeforeUpdate)
  }

  @Test("消えたスニペットのベクトルを消す")
  func deletesEmbeddingOfDeletedSnippet() throws {
    let modelContext = ModelContext(try makeTanzakuModelContainer(storeLocation: .inMemory, syncedStoreCloudKitDatabase: .none))
    let snippet = Snippet(body: "echo dummy")
    modelContext.insert(snippet)
    let embedder = characterCountEmbedder(modelIdentifier: "dummy-model")
    try updateSnippetEmbeddings(modelContext: modelContext, embedder: embedder)
    try modelContext.save()

    modelContext.delete(snippet)
    try modelContext.save()
    try updateSnippetEmbeddings(modelContext: modelContext, embedder: embedder)

    #expect(try modelContext.fetchCount(FetchDescriptor<SnippetEmbedding>()) == 0)
  }

  @Test("ベクトルは長さ 1 にそろえて保存し、同じ値に読み戻せる")
  func vectorIsNormalizedAndRoundTrips() {
    let normalizedVector = l2NormalizedVector(vector: [3, 4])
    #expect(normalizedVector == [0.6, 0.8])
    #expect(snippetEmbeddingVector(data: snippetEmbeddingVectorData(vector: normalizedVector)) == normalizedVector)
    #expect(l2NormalizedVector(vector: [0, 0]) == [0, 0])
  }
}
