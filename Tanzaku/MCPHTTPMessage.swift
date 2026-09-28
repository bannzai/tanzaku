import Foundation

/// MCP のエンドポイントに届いた HTTP リクエスト。
struct MCPHTTPRequest: Equatable {
  /// `POST` などのメソッド。
  var method: String
  /// クエリを含むリクエストのパス。
  var path: String
  /// ヘッダー名は大文字と小文字を区別しないため (RFC 9110 5.1)、名前を小文字にそろえて持つ。
  var headers: [String: String]
  /// リクエストの本文。
  var body: Data
}

/// MCP のエンドポイントが返す HTTP レスポンス。
struct MCPHTTPResponse: Equatable {
  /// ステータスコード。
  var statusCode: Int
  /// `Content-Type`・`Content-Length`・`Connection` 以外のヘッダー。この 3 つは `serializedMCPHTTPResponse(response:)` が付ける。
  var headers: [String: String]
  /// レスポンスの本文。JSON-RPC の応答か空。
  var body: Data
}

/// 受け取ったバイト列を HTTP リクエストとして読んだ結果。
enum MCPHTTPRequestParseResult: Equatable {
  /// ヘッダーか本文の途中までしか届いていない。続きを受け取ってから読み直す。
  case incomplete
  /// 1 つのリクエストを読み終えた。
  case complete(MCPHTTPRequest)
  /// HTTP のリクエストとして読めない。返すステータスコードを持つ。
  case invalid(statusCode: Int)
}

/// 受け付ける本文の最大のバイト数。スニペットはテキストで 1 MiB あれば足り、localhost の別のプロセスから巨大な本文を送られてもメモリを使い切らないための上限。
let mcpHTTPMaximumBodyByteCount = 1_048_576

/// 受け付けるヘッダーの最大のバイト数。MCP のクライアントが送るヘッダーは数百バイトで、終わりの無いヘッダーを送られても受け取り続けないための上限。
let mcpHTTPMaximumHeaderByteCount = 65_536

/// 受け取ったバイト列を HTTP/1.1 のリクエストとして読む。
///
/// 1 つの接続で 1 つのリクエストだけを扱い、応答の後に接続を閉じる (`Connection: close`) ため、本文は `Content-Length` の長さだけ読む。
/// MCP のクライアントは JSON-RPC のメッセージを 1 つずつ POST し、本文の長さが送る前に決まっているため、`Transfer-Encoding: chunked` は受け付けない。
func parseMCPHTTPRequest(data: Data) -> MCPHTTPRequestParseResult {
  guard let headerEndRange = data.range(of: Data("\r\n\r\n".utf8)) else {
    return data.count > mcpHTTPMaximumHeaderByteCount ? .invalid(statusCode: 431) : .incomplete
  }
  guard headerEndRange.lowerBound - data.startIndex <= mcpHTTPMaximumHeaderByteCount,
    let headerText = String(data: data[data.startIndex..<headerEndRange.lowerBound], encoding: .utf8)
  else {
    return .invalid(statusCode: 400)
  }
  let headerLines = headerText.components(separatedBy: "\r\n")
  let requestLineParts = headerLines[0].split(separator: " ", omittingEmptySubsequences: false)
  guard requestLineParts.count == 3, requestLineParts[2].hasPrefix("HTTP/1.") else {
    return .invalid(statusCode: 400)
  }
  var headers: [String: String] = [:]
  for line in headerLines.dropFirst() {
    guard let colonIndex = line.firstIndex(of: ":") else {
      return .invalid(statusCode: 400)
    }
    headers[line[..<colonIndex].lowercased()] = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
  }
  if headers["transfer-encoding"] != nil {
    return .invalid(statusCode: 411)
  }
  guard let contentLength = Int(headers["content-length"] ?? "0"), contentLength >= 0 else {
    return .invalid(statusCode: 400)
  }
  guard contentLength <= mcpHTTPMaximumBodyByteCount else {
    return .invalid(statusCode: 413)
  }
  guard data.endIndex - headerEndRange.upperBound >= contentLength else {
    return .incomplete
  }
  return .complete(
    MCPHTTPRequest(
      method: String(requestLineParts[0]),
      path: String(requestLineParts[1]),
      headers: headers,
      body: Data(data[headerEndRange.upperBound..<headerEndRange.upperBound + contentLength])
    )
  )
}

/// レスポンスを HTTP/1.1 のバイト列にする。1 つの接続で 1 つのリクエストだけを扱うため、常に `Connection: close` を付ける。
func serializedMCPHTTPResponse(response: MCPHTTPResponse) -> Data {
  var headerLines = ["HTTP/1.1 \(response.statusCode) \(mcpHTTPReasonPhrase(statusCode: response.statusCode))"]
  if !response.body.isEmpty {
    headerLines.append("Content-Type: application/json")
  }
  headerLines.append("Content-Length: \(response.body.count)")
  headerLines.append("Connection: close")
  headerLines += response.headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
  return Data((headerLines.joined(separator: "\r\n") + "\r\n\r\n").utf8) + response.body
}

/// ステータス行の理由句 (RFC 9110 15)。`HTTPURLResponse.localizedString(forStatusCode:)` は端末の言語に訳されるため使わない。
/// 理由句はクライアントが解釈しないため (RFC 9112 4)、このサーバーが返さないステータスコードは空にする。
func mcpHTTPReasonPhrase(statusCode: Int) -> String {
  switch statusCode {
  case 200: "OK"
  case 202: "Accepted"
  case 400: "Bad Request"
  case 401: "Unauthorized"
  case 403: "Forbidden"
  case 404: "Not Found"
  case 405: "Method Not Allowed"
  case 411: "Length Required"
  case 413: "Content Too Large"
  case 431: "Request Header Fields Too Large"
  case 500: "Internal Server Error"
  default: ""
  }
}
