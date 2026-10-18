import Foundation
import SwiftData

/// Jev (TypeSafe の判定 API) の判定のエンドポイント ( https://docs.typesafe.ai/api.md )。
let jevAPIEndpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!

/// Jev に渡すモデルの名前。TypeSafe の API の説明で最新の主力のモデルを指す名前 ( https://docs.typesafe.ai/api.md )。
let jevModelName = "jev-latest"

/// Jev に並べ替えさせる候補の件数。埋め込みの類似度の上位からこの件数を渡す。
///
/// 2026-10-19 の手元の Mac から実際の API を呼んだ実測 (`SemanticSearchJevComparisonTests`) で、測った件数 (10・15・20・26) のうち上位 3 件の割合が目標 (0.6) を超えた最小の件数 (1 回の測定)。
/// 10 件は 2 回の測定で 15/26・16/26 (0.577・0.615) と目標をまたぎ、15 件は 20/26 (0.769)、20 件は 21/26、26 件 (fixture のすべて) は 26/26 だった。
/// 送るトークンは件数にほぼ比例する (1 回の入力の中央値は 10 件で 1324、15 件で 1841、26 件で 2950) ため、目標を超える最小の件数にした。
/// 設定の Jev の欄 (Mac) が送る件数を説明に出すため public にする。
public let jevRerankCandidateCount = 15

/// Jev に送る前に待つ時間。打つたびに送らず、入力が止まった時だけ送るため。
/// ランチャーは打つたびに前の検索を取り消す (`LauncherPanelController.search`) ため、この間に次の文字を打つと送らずに終わる。
/// 0.3 秒は打鍵の間隔 (速く打つ時は 0.1〜0.2 秒) より長く、2026-10-19 の実測の Jev の応答の中央値 (0.17 秒) と足しても 0.5 秒に収まる長さ。
let jevRequestDelay = Duration.milliseconds(300)

/// Jev の要求で、データが届かない時間の上限 (秒。`URLRequest.timeoutInterval`)。超えたら失敗として今の意味検索 (埋め込み + しきい値) に戻る。
/// 応答全体の上限ではなく、少しずつデータが届き続ける間は待ち続ける。
/// 既定の 60 秒のままだと、通信が詰まった間はランチャーの意味検索の欄が出ないため短くする。2026-10-19 の実測の 1 回の要求は p90 で 0.21 秒以下だったため、
/// その 10 倍ほどの 2 秒にし、遅い回線でも通常は待ちきれる長さにした。
let jevRequestTimeoutSeconds: TimeInterval = 2

/// Jev に渡す候補 1 件のテキストの最大の文字数。キーワード・タイトル・本文の先頭で用途は分かり、送る本文を減らすため。
let jevRerankCandidateMaxLength = 200

/// Jev の答え (0〜1) がこの値より大きい候補だけを意味検索の結果に出す。Noul は「はい」の確からしさを返すため、「はい」が「いいえ」より確からしい境目にした。
let jevRerankMinimumNoul = 0.5

/// Jev の判定の要求の本文 ( https://docs.typesafe.ai/api.md の Request body )。
struct JevRequest: Encodable {
  /// 判定させる内容。検索語と、番号を付けた候補のテキスト。
  var state: JevRequestState
  /// 使うモデルの名前。
  var model: String
  /// 判定させる問い。キーは候補の番号 (`jevCandidateQuestionID(candidateIndex:)`) で、答えも同じキーで返る。
  var questions: [String: JevNoulQuestion]
}

/// Jev に判定させる内容。
struct JevRequestState: Encodable {
  /// 利用者が打った検索語 (秘匿情報らしい文字列を伏せたもの)。
  var query: String
  /// 候補のテキスト (秘匿情報らしい文字列を伏せ、先頭だけにしたもの)。キーは問いと同じ候補の番号。
  var snippets: [String: String]
}

/// Jev の「はい・いいえ」の問い (type `noul`)。
struct JevNoulQuestion: Encodable {
  /// 問いの種類。常に `noul`。
  var type = "noul"
  /// 問いの文。
  var instructions: String
}

/// Jev の判定の応答の本文のうち、使う部分 ( https://docs.typesafe.ai/api.md の Response body )。
struct JevResponse: Decodable {
  /// 問いのキーごとの答え。
  var answers: [String: JevNoulAnswer]
}

/// Jev の「はい・いいえ」の問いの答え。
struct JevNoulAnswer: Decodable {
  /// 「はい」の確からしさ (0〜1)。
  var noul: Double
}

/// Jev の要求が失敗した。`description` には HTTP の状態コードだけを入れ、API キー・検索語・スニペットの本文を入れない (`.claude/rules/snippet-content-handling.md`)。
public struct JevRequestError: Error, CustomStringConvertible {
  /// HTTP の状態コード。HTTP の応答でなかった時は `nil`。
  public var statusCode: Int?

  public var description: String {
    "Jev request failed (HTTP status \(statusCode.map(String.init) ?? "none"))"
  }
}

/// 候補の番号から作る、Jev の問いと候補のテキストのキー。
func jevCandidateQuestionID(candidateIndex: Int) -> String {
  "snippet_\(candidateIndex + 1)"
}

/// 秘匿情報らしい文字列を `[REDACTED]` に置き換える。Jev へ送る前に検索語と候補のテキストに掛ける (`.claude/rules/snippet-content-handling.md`)。
///
/// 伏せるのは、秘密鍵の PEM のブロック、名前に TOKEN・SECRET・PASSWORD・API_KEY などを含む変数への代入の値、`Authorization` の値 (長さによらない) と Bearer・Basic の後の 16 文字以上の値、URL の中の利用者名とパスワード、
/// 決まった接頭辞を持つ API キー (OpenAI・GitHub・Slack・AWS・Google)、英字と数字を両方含む 32 文字以上の切れ目の無い文字列 (`/` で切れる)。これに当たらない秘匿情報は伏せられない。
func snippetTextMaskingSecrets(text: String) -> String {
  let replacements: [(pattern: String, template: String)] = [
    (#"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?(-----END [A-Z ]*PRIVATE KEY-----|$)"#, "[REDACTED]"),
    // 引用符で囲んだ値は空白やエスケープした引用符 (`\"`) を含んでも閉じる引用符まで伏せる。名前も引用符で囲む JSON・YAML (`"password": "..."`) を含める。
    (
      #"(?i)\b([A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|PASSWD|API_?KEY|ACCESS_?KEY|PRIVATE_?KEY|CREDENTIAL)[A-Z0-9_]*["']?\s*[:=]\s*)(["'])(?:\\.|(?!\2)[^\\\n])*\2"#,
      "$1$2[REDACTED]$2"
    ),
    // 閉じる引用符が同じ行に無い値 (閉じ忘れ・複数行の値)。上で伏せた値を伏せ直さないよう `[REDACTED]` で始まる値は除き、行末まで伏せる。
    (
      #"(?i)\b([A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|PASSWD|API_?KEY|ACCESS_?KEY|PRIVATE_?KEY|CREDENTIAL)[A-Z0-9_]*["']?\s*[:=]\s*)(["'])(?!\[REDACTED\])[^\n]*"#,
      "$1$2[REDACTED]"
    ),
    // 引用符の無い値。`,` を含む値 (`PASSWORD=ab,cd`) も伏せるよう、空白と `}` までを値とする。上で伏せた値は除く。
    (
      #"(?i)\b([A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|PASSWD|API_?KEY|ACCESS_?KEY|PRIVATE_?KEY|CREDENTIAL)[A-Z0-9_]*["']?\s*[:=]\s*)(?!["'\[])[^\s}]+"#,
      "$1[REDACTED]"
    ),
    // `Authorization` の値は短い Basic 認証 (`dummy:x` の Base64 等) でも秘匿情報のため、長さによらず伏せる。
    (#"(?i)(\bauthorization["']?\s*[:=]\s*["']?(?:bearer|basic|token|digest)?\s*)[^\s"']+"#, "$1[REDACTED]"),
    (#"(?i)\b(bearer|basic)\s+[A-Za-z0-9\-._~+/]{16,}=*"#, "$1 [REDACTED]"),
    (#"://[^/\s:@]+:[^/\s@]+@"#, "://[REDACTED]@"),
    (
      #"\b(sk-[A-Za-z0-9_\-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[abprs]-[A-Za-z0-9\-]{10,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_\-]{35})"#,
      "[REDACTED]"
    ),
  ]
  // パターンはこの関数の中の固定の文字列で、作れなければ実装の誤りのため止める。
  let maskedText = replacements.reduce(text) { maskedText, replacement in
    try! NSRegularExpression(pattern: replacement.pattern).stringByReplacingMatches(
      in: maskedText,
      range: NSRange(maskedText.startIndex..., in: maskedText),
      withTemplate: replacement.template
    )
  }
  // 英字と数字を両方含む 32 文字以上の切れ目の無い文字列。英字と数字の有無を正規表現の先読みで調べると、長い英字だけの文字列で走査が文字数の二乗になるため、
  // 切れ目の無い文字列を一度だけ取り出してから調べる。`/` を含めると数字を含むファイルのパスまで伏せ、検索に効く語が消えるため含めない。
  // 後ろの一致から置き換え、前の一致の位置をずらさない。
  return try! NSRegularExpression(pattern: #"[A-Za-z0-9_\-+=]{32,}"#)
    .matches(in: maskedText, range: NSRange(maskedText.startIndex..., in: maskedText))
    .reversed()
    .reduce(maskedText) { maskedText, match in
      guard let range = Range(match.range, in: maskedText),
        maskedText[range].contains(where: \.isLetter),
        maskedText[range].contains(where: \.isNumber)
      else {
        return maskedText
      }
      return maskedText.replacingCharacters(in: range, with: "[REDACTED]")
    }
}

/// 検索語と候補のテキストから、Jev の判定の要求を作る。候補のテキストは秘匿情報らしい文字列を伏せてから先頭 `jevRerankCandidateMaxLength` 文字にする。
func jevRerankRequest(query: String, candidateTexts: [String], apiKey: String) throws -> URLRequest {
  var request = URLRequest(url: jevAPIEndpoint)
  request.httpMethod = "POST"
  request.timeoutInterval = jevRequestTimeoutSeconds
  request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
  request.setValue("application/json", forHTTPHeaderField: "Content-Type")
  request.httpBody = try JSONEncoder().encode(
    JevRequest(
      state: JevRequestState(
        query: snippetTextMaskingSecrets(text: query),
        snippets: Dictionary(
          uniqueKeysWithValues: candidateTexts.indices.map { candidateIndex in
            (
              jevCandidateQuestionID(candidateIndex: candidateIndex),
              String(snippetTextMaskingSecrets(text: candidateTexts[candidateIndex]).prefix(jevRerankCandidateMaxLength))
            )
          }
        )
      ),
      model: jevModelName,
      questions: Dictionary(
        uniqueKeysWithValues: candidateTexts.indices.map { candidateIndex in
          let questionID = jevCandidateQuestionID(candidateIndex: candidateIndex)
          return (
            questionID,
            JevNoulQuestion(
              instructions:
                "The snippets are reusable text, shell commands, code, or prompts saved in a snippet app. Is \(questionID) what the user is looking for with the search query? The query may use different words or another language than the snippet. Answer yes only when the snippet serves the purpose of the query."
            )
          )
        }
      )
    )
  )
  return request
}

/// Jev の応答から、答えが `jevRerankMinimumNoul` より大きい候補の添字 (`candidateCount` 未満) を、答えの大きい順に最大 `semanticMatchLimit` 件返す。
func jevRerankedCandidateIndices(response: JevResponse, candidateCount: Int) -> [Int] {
  Array(
    (0..<candidateCount)
      .compactMap { candidateIndex -> (candidateIndex: Int, noul: Double)? in
        response.answers[jevCandidateQuestionID(candidateIndex: candidateIndex)].map { (candidateIndex, $0.noul) }
      }
      .filter { $0.noul > jevRerankMinimumNoul }
      .sorted { $0.noul > $1.noul }
      .prefix(semanticMatchLimit)
      .map(\.candidateIndex)
  )
}

/// 候補のテキストを Jev に判定させ、検索語に当てはまる候補の添字を当てはまる順に返す。
/// HTTP の状態コードが 2xx でない時は `JevRequestError` を投げる。
/// 冪等ではない: 外部の API の応答で決まり、同じ入力でもモデルの更新で結果が変わり得る。
/// `sendJevRequest` を呼び出し側と同じ actor で呼ぶため (Sendable でないクロージャを渡せるようにするため) MainActor にする。
@MainActor
func jevRerankedCandidateIndices(
  query: String,
  candidateTexts: [String],
  apiKey: String,
  sendJevRequest: (URLRequest) async throws -> (Data, URLResponse)
) async throws -> [Int] {
  // 秘匿情報を伏せる処理は候補の本文の全文に掛かり (200 文字に切る前に伏せないと、境目をまたぐ秘密値の一部が残るため)、長い本文ではメインスレッドを止めるため、メインの外で作る。
  let request = try await Task.detached(priority: .userInitiated) {
    try jevRerankRequest(query: query, candidateTexts: candidateTexts, apiKey: apiKey)
  }.value
  let (data, response) = try await sendJevRequest(request)
  guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
    throw JevRequestError(statusCode: (response as? HTTPURLResponse)?.statusCode)
  }
  return jevRerankedCandidateIndices(response: try JSONDecoder().decode(JevResponse.self, from: data), candidateCount: candidateTexts.count)
}

/// Mac のランチャーの検索。`searchSnippets(query:modelContext:embedder:)` に、Jev による意味検索の並べ替えを足したもの。
///
/// `jevAPIKey` が `nil` の時・`embedder` が `nil` の時・候補が無い時は Jev を呼ばず、`searchSnippets(query:modelContext:embedder:)` と同じ結果を返す。
/// Jev を呼ぶ時は、`jevRequestDelay` 待ってから、文字列で一致したものを除いたスニペットのうち埋め込みの類似度の上位 `jevRerankCandidateCount` 件を渡し、Jev が当てはまると答えたものを意味検索の結果にする。
/// Jev の要求が失敗した時は `onJevError` を呼び、`searchSnippets(query:modelContext:embedder:)` と同じ結果を返す (取り消された時は `CancellationError` を投げる)。
/// 冪等ではない: Jev を呼ぶ時は外部の API の応答で結果が決まる。
@MainActor
public func searchSnippets(
  query: String,
  modelContext: ModelContext,
  embedder: SnippetTextEmbedder?,
  jevAPIKey: String?,
  sendJevRequest: (URLRequest) async throws -> (Data, URLResponse),
  onJevError: (Error) -> Void
) async throws -> SnippetSearchResult {
  let searchResult = try searchSnippets(query: query, modelContext: modelContext, embedder: embedder)
  guard let jevAPIKey, let embedder else {
    return searchResult
  }
  let keywordMatchedSnippetIDs = Set(searchResult.keywordMatches.map(\.snippet.id))
  let candidateSnippets = try semanticSnippetMatches(
    query: query,
    snippets: try modelContext.fetch(FetchDescriptor<Snippet>()).filter { !keywordMatchedSnippetIDs.contains($0.id) },
    modelContext: modelContext,
    embedder: embedder,
    limit: jevRerankCandidateCount,
    minimumSimilarity: -.infinity
  )
  guard !candidateSnippets.isEmpty else {
    return searchResult
  }
  try await Task.sleep(for: jevRequestDelay)
  do {
    let candidateIndices = try await jevRerankedCandidateIndices(
      query: query,
      candidateTexts: candidateSnippets.map { snippetEmbeddingSourceText(snippet: $0) },
      apiKey: jevAPIKey,
      sendJevRequest: sendJevRequest
    )
    return SnippetSearchResult(keywordMatches: searchResult.keywordMatches, semanticMatches: candidateIndices.map { candidateSnippets[$0] })
  } catch {
    try Task.checkCancellation()
    onJevError(error)
    return searchResult
  }
}
