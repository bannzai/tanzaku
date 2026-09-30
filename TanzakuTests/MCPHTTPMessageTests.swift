import Foundation
import Testing

@testable import Tanzaku

/// `parseMCPHTTPRequest(data:)` と `serializedMCPHTTPResponse(response:)` を、MCP のクライアントが送る形のバイト列で確かめる。
struct MCPHTTPMessageTests {
  @Test("ヘッダーと Content-Length の長さの本文を読み、ヘッダー名を小文字にそろえる")
  func parsesCompleteRequest() {
    let body = #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#
    let data = Data("POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:47831\r\nAuthorization: Bearer dummy-token-for-test\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)".utf8)

    #expect(
      parseMCPHTTPRequest(data: data)
        == .complete(
          MCPHTTPRequest(
            method: "POST",
            path: "/mcp",
            headers: ["host": "127.0.0.1:47831", "authorization": "Bearer dummy-token-for-test", "content-length": "\(body.utf8.count)"],
            body: Data(body.utf8)
          )
        )
    )
  }

  @Test("ヘッダーの終わりか本文の最後まで届いていなければ続きを待つ")
  func waitsForRemainingBytes() {
    #expect(parseMCPHTTPRequest(data: Data("POST /mcp HTTP/1.1\r\nContent-Length: 10\r\n".utf8)) == .incomplete)
    #expect(parseMCPHTTPRequest(data: Data("POST /mcp HTTP/1.1\r\nContent-Length: 10\r\n\r\n{}".utf8)) == .incomplete)
  }

  @Test("HTTP として読めないリクエスト・chunked・上限を超える本文は、返すステータスコードを付けて拒む")
  func rejectsInvalidRequest() {
    #expect(parseMCPHTTPRequest(data: Data("hello\r\n\r\n".utf8)) == .invalid(statusCode: 400))
    #expect(parseMCPHTTPRequest(data: Data("POST /mcp HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n".utf8)) == .invalid(statusCode: 411))
    #expect(
      parseMCPHTTPRequest(data: Data("POST /mcp HTTP/1.1\r\nContent-Length: \(mcpHTTPMaximumBodyByteCount + 1)\r\n\r\n".utf8)) == .invalid(statusCode: 413)
    )
  }

  @Test("レスポンスに Content-Length と Connection: close を付け、本文があれば JSON の Content-Type を付ける")
  func serializesResponse() {
    let response = MCPHTTPResponse(statusCode: 202, headers: [:], body: Data())
    #expect(String(decoding: serializedMCPHTTPResponse(response: response), as: UTF8.self) == "HTTP/1.1 202 Accepted\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")

    let jsonResponse = MCPHTTPResponse(statusCode: 200, headers: [:], body: Data("{}".utf8))
    #expect(
      String(decoding: serializedMCPHTTPResponse(response: jsonResponse), as: UTF8.self)
        == "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}"
    )
  }
}
