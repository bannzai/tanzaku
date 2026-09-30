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
  guard let preferredLanguage = preferredLanguages.first else {
    return .english
  }
  let language = Locale.Language(identifier: preferredLanguage)
  // NLLanguage の中国語は書記体系ごとに別の値 (zh-Hans / zh-Hant) で、言語コードの `zh` だけではモデルが見つからない。
  // `zh-TW` のように書記体系を書かない指定もあるため、推定した書記体系 (maximalIdentifier) で選ぶ。
  if language.languageCode == .chinese {
    return Locale.Language(identifier: language.maximalIdentifier).script == .hanTraditional ? .traditionalChinese : .simplifiedChinese
  }
  return NLLanguage(rawValue: language.languageCode?.identifier ?? "en")
}

/// 端末に NLContextualEmbedding の資産があれば、それを使う埋め込みモデルを作る。資産のダウンロードが済んでいない時と、言語に対応するモデルが無い時は `nil` を返し、呼び出し側は意味検索なしで検索する。
///
/// 文章のベクトルは、トークンごとのベクトルの平均にする。NLContextualEmbedding は文章全体のベクトルを返さず、平均は追加の学習なしで文章の意味を表す標準的な集約のため。
///
/// NLContextualEmbedding は `maximumSequenceLength` を超えた入力の末尾を切り捨てるため、文章を区切ってから区切りごとにトークンのベクトルを集め、全体で平均する。
public func makeContextualSnippetTextEmbedder(language: NLLanguage) throws -> SnippetTextEmbedder? {
  guard let embedding = NLContextualEmbedding(language: language), embedding.hasAvailableAssets else {
    return nil
  }
  try embedding.load()
  return SnippetTextEmbedder(modelIdentifier: "\(embedding.modelIdentifier)@\(embedding.revision)") { text in
    var sum = [Double](repeating: 0, count: embedding.dimension)
    var tokenCount = 0
    try enumerateContextualTokenVectors(embedding: embedding, language: language, text: text) { _, tokenVector, _ in
      for index in sum.indices {
        sum[index] += tokenVector[index]
      }
      tokenCount += 1
    }
    // トークンが無い文章 (空文字) は 0 で割らずに 0 のベクトルにするため、割る数の下限を 1 にする。0 のベクトルは検索で比べない (`semanticSnippetMatches`)。
    return sum.map { Float($0 / Double(max(tokenCount, 1))) }
  }
}

/// 文章を `maximumSequenceLength` に収まる長さに区切り、区切りごとのトークンのベクトルを 1 つずつ `body` に渡す。`embedding` は読み込み (`load()`) 済みのもの。
///
/// `body` には区切りの番号 (0 から)、トークンのベクトル、そのトークンが表す区切りの中の文字の範囲を渡す。範囲が空のトークンは、文字に対応しない特別なトークン (区切りの先頭に付く) を表す。
/// 長い本文でも全トークンのベクトルを同時に持たずに集約できるよう、配列にまとめず 1 つずつ渡す。
func enumerateContextualTokenVectors(
  embedding: NLContextualEmbedding,
  language: NLLanguage,
  text: String,
  body: (_ chunkIndex: Int, _ tokenVector: [Double], _ tokenRange: Range<String.Index>) -> Void
) throws {
  // 漢字かなのモデルは 1 文字がおよそ 1 トークンで、ラテン文字のモデルは 1 トークンが複数の文字になる。
  // 文字数を上限の半分にすれば、1 文字が 2 トークンに分かれる文字や先頭・末尾の特別なトークンがあっても上限に収まるため。
  let chunkCharacterCount = max(embedding.maximumSequenceLength / 2, 1)
  var chunkIndex = 0
  var chunkStartIndex = text.startIndex
  while chunkStartIndex < text.endIndex {
    let chunkEndIndex = text.index(chunkStartIndex, offsetBy: chunkCharacterCount, limitedBy: text.endIndex) ?? text.endIndex
    let chunk = String(text[chunkStartIndex..<chunkEndIndex])
    try embedding.embeddingResult(for: chunk, language: language).enumerateTokenVectors(in: chunk.startIndex..<chunk.endIndex) { tokenVector, tokenRange in
      body(chunkIndex, tokenVector, tokenRange)
      return true
    }
    chunkIndex += 1
    chunkStartIndex = chunkEndIndex
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
