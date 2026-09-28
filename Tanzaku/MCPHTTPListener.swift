import Foundation
import Network
import os

/// MCP のサーバーの待ち受けの状態。設定の「状態」に表示する。
enum MCPServerState: Equatable {
  /// 設定で止めている。
  case stopped
  /// ポートを開いている途中。
  case starting
  /// 待ち受けている。
  case running(port: Int)
  /// ポートを開けなかった (ほかのアプリが同じポートを使っている時など)。
  case failed(message: String)
}

/// MCP のサーバーのログ。リクエストのメソッド・パス・ステータスコードだけを書き、本文とトークンは書かない (`.claude/rules/snippet-content-handling.md`)。
let mcpServerLogger = Logger(subsystem: "com.bannzai.tanzaku", category: "MCP")

/// 1 回に受け取る最大のバイト数。MCP のリクエストは数 KB で、大きな本文は複数回に分けて受け取る。
private let mcpHTTPReceiveChunkByteCount = 65_536

/// 127.0.0.1 の TCP のポートで HTTP のリクエストを待ち受け、`handler` が返したレスポンスを返す。
///
/// ほかの Mac から届かないよう、ループバックのアドレスだけで待ち受ける (Streamable HTTP「Security & Endpoint」)。
/// コールバックはメインキューで受ける。リクエストの処理はスニペットのストア (`ModelContainer.mainContext`) を使い、メインアクターで行うため。
func startMCPHTTPListener(
  port: Int,
  handler: @escaping @MainActor @Sendable (MCPHTTPRequest) async -> MCPHTTPResponse,
  stateDidChange: @escaping @MainActor @Sendable (MCPServerState) -> Void
) throws -> NWListener {
  let parameters = NWParameters.tcp
  parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(integerLiteral: UInt16(port)))
  let listener = try NWListener(using: parameters)
  listener.stateUpdateHandler = { @Sendable [weak listener] state in
    MainActor.assumeIsolated {
      switch state {
      case .setup:
        stateDidChange(.starting)
      case .ready:
        stateDidChange(.running(port: port))
      case .waiting(let error), .failed(let error):
        // ポートが使われている時は waiting のまま再試行し続けるため、待ち受けを止めて失敗として表示する。
        mcpServerLogger.error("MCP listener failed: \(error.localizedDescription, privacy: .public)")
        listener?.cancel()
        stateDidChange(.failed(message: error.localizedDescription))
      case .cancelled:
        break
      @unknown default:
        break
      }
    }
  }
  listener.newConnectionHandler = { @Sendable connection in
    MainActor.assumeIsolated {
      connection.start(queue: .main)
      receiveMCPHTTPRequest(connection: connection, receivedData: Data(), handler: handler)
    }
  }
  listener.start(queue: .main)
  return listener
}

/// 1 つのリクエストを読み終えるまで受け取り、レスポンスを返して接続を閉じる。
private func receiveMCPHTTPRequest(
  connection: NWConnection,
  receivedData: Data,
  handler: @escaping @MainActor @Sendable (MCPHTTPRequest) async -> MCPHTTPResponse
) {
  connection.receive(minimumIncompleteLength: 1, maximumLength: mcpHTTPReceiveChunkByteCount) { @Sendable content, _, isComplete, error in
    MainActor.assumeIsolated {
      let data = receivedData + (content ?? Data())
      switch parseMCPHTTPRequest(data: data) {
      case .incomplete:
        if isComplete || error != nil {
          connection.cancel()
          return
        }
        receiveMCPHTTPRequest(connection: connection, receivedData: data, handler: handler)
      case .invalid(let statusCode):
        sendMCPHTTPResponse(connection: connection, response: MCPHTTPResponse(statusCode: statusCode, headers: [:], body: Data()))
      case .complete(let request):
        Task { @MainActor in
          let response = await handler(request)
          mcpServerLogger.info("\(request.method, privacy: .public) \(request.path, privacy: .public) -> \(response.statusCode)")
          sendMCPHTTPResponse(connection: connection, response: response)
        }
      }
    }
  }
}

/// レスポンスを送り、送り終えたら接続を閉じる。
private func sendMCPHTTPResponse(connection: NWConnection, response: MCPHTTPResponse) {
  connection.send(
    content: serializedMCPHTTPResponse(response: response),
    completion: .contentProcessed { @Sendable _ in
      connection.cancel()
    }
  )
}
