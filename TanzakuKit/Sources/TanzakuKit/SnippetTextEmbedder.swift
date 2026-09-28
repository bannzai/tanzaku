import Foundation
import NaturalLanguage

/// 文章を意味検索のベクトルにする埋め込みモデル。アプリでは `makeContextualSnippetTextEmbedder(language:)` で作り、テストでは埋め込みモデルの資産が無くても動く偽の実装を渡す。
public struct SnippetTextEmbedder {
  /// ベクトルを作る埋め込みモデルとその版。`SnippetEmbedding.modelIdentifier` に入れ、一致しないベクトルは検索に使わない。
  public var modelIdentifier: String
  /// 文章からベクトルを作る。長さはそろっていればよく、正規化は呼び出し側で行う。
  public var vector: (String) throws -> [Float]

  /// モジュールの外で偽の実装を作れるよう public にする。
  public init(modelIdentifier: String, vector: @escaping (String) throws -> [Float]) {
    self.modelIdentifier = modelIdentifier
    self.vector = vector
  }
}

/// 端末の優先言語から、意味検索に使う NLContextualEmbedding の言語を選ぶ。
///
/// NLContextualEmbedding は文字の種類ごと (ラテン文字・漢字かな・キリル文字など) に別のモデルで、別のモデルのベクトルは比べられない。
/// スニペットとクエリを同じモデルに通すため、端末で 1 つの言語に決める。ユーザーが普段書く言語は端末の優先言語と一致しやすいため、それを使う。
public func snippetEmbeddingLanguage(preferredLanguages: [String]) -> NLLanguage {
  // 優先言語が無い環境は無いが、あればアプリの開発言語 (英語) にそろえる。
  NLLanguage(rawValue: preferredLanguages.first.flatMap { Locale(identifier: $0).language.languageCode?.identifier } ?? "en")
}

/// 端末に NLContextualEmbedding の資産があれば、それを使う埋め込みモデルを作る。資産のダウンロードが済んでいない時と、言語に対応するモデルが無い時は `nil` を返し、呼び出し側は意味検索なしで検索する。
///
/// 文章のベクトルは、トークンごとのベクトルの平均にする。NLContextualEmbedding は文章全体のベクトルを返さず、平均は追加の学習なしで文章の意味を表す標準的な集約のため。
public func makeContextualSnippetTextEmbedder(language: NLLanguage) throws -> SnippetTextEmbedder? {
  guard let embedding = NLContextualEmbedding(language: language), embedding.hasAvailableAssets else {
    return nil
  }
  try embedding.load()
  return SnippetTextEmbedder(modelIdentifier: "\(embedding.modelIdentifier)@\(embedding.revision)") { text in
    var sum = [Double](repeating: 0, count: embedding.dimension)
    var tokenCount = 0
    try embedding.embeddingResult(for: text, language: language).enumerateTokenVectors(in: text.startIndex..<text.endIndex) { tokenVector, _ in
      for index in sum.indices {
        sum[index] += tokenVector[index]
      }
      tokenCount += 1
      return true
    }
    return sum.map { Float($0 / Double(max(tokenCount, 1))) }
  }
}

/// NLContextualEmbedding の資産をダウンロードする。ダウンロード済みか、ダウンロードできた時に `true` を返す。
///
/// 資産はモデルごとに OS が管理し、アプリをまたいで共有される。ダウンロードが終わるまで意味検索は使えないため、アプリの起動時に呼ぶ。
public func requestContextualEmbeddingAssets(language: NLLanguage) async throws -> Bool {
  guard let embedding = NLContextualEmbedding(language: language) else {
    return false
  }
  if embedding.hasAvailableAssets {
    return true
  }
  return try await embedding.requestAssets() == .available
}
