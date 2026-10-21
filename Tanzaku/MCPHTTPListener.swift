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
  /// ほかのプロセスが同じポートを使っていて開けなかった。
  /// 登録済みのクライアントはそのプロセスへトークンを送っている恐れがあるため、ほかの失敗と分けて警告する。
  case portInUse(port: Int)
  /// ポートを開けなかった (ポートの使用中以外の理由)。
  case failed(message: String)
}

/// 待ち受けを始められなかった時の状態。
///
/// `EADDRINUSE` は、このアプリが応答の後に閉じた接続の TIME_WAIT や解放前の自分のソケットでも返る。
/// そのため `isPortAcceptingConnections` (そのポートへ接続できた = ほかのプロセスが待ち受けている) の時だけ `portInUse` にし、ほかのアプリへトークンを送っている恐れを警告する。
func mcpServerFailedState(error: Error, port: Int, isPortAcceptingConnections: Bool) -> MCPServerState {
  if case .posix(.EADDRINUSE) = error as? NWError, isPortAcceptingConnections {
    return .portInUse(port: port)
  }
  return .failed(message: error.localizedDescription)
}

/// 127.0.0.1 の `port` へ TCP で接続できるか (ほかのプロセスが待ち受けているか)。接続できたらすぐ閉じ、何も送らない。
///
/// 待ち受けの失敗時にだけメインキューから呼ぶ。ループバックへの接続は通常すぐ成否が決まるが、相手の受け入れ待ちの列が詰まっていると決まらないため、0.5 秒で打ち切って「接続できない」とする。
nonisolated func isLoopbackPortAcceptingConnections(port: Int) -> Bool {
  let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
  guard socketDescriptor >= 0 else {
    return false
  }
  defer {
    close(socketDescriptor)
  }
  _ = fcntl(socketDescriptor, F_SETFL, fcntl(socketDescriptor, F_GETFL) | O_NONBLOCK)
  var address = sockaddr_in()
  address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
  address.sin_family = sa_family_t(AF_INET)
  address.sin_port = in_port_t(UInt16(port).bigEndian)
  address.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)
  let connectResult = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      connect(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
    }
  }
  if connectResult == 0 {
    return true
  }
  guard errno == EINPROGRESS else {
    return false
  }
  var pollDescriptor = pollfd(fd: socketDescriptor, events: Int16(POLLOUT), revents: 0)
  guard poll(&pollDescriptor, 1, 500) == 1 else {
    return false
  }
  var socketError: Int32 = 0
  var socketErrorLength = socklen_t(MemoryLayout<Int32>.size)
  return getsockopt(socketDescriptor, SOL_SOCKET, SO_ERROR, &socketError, &socketErrorLength) == 0 && socketError == 0
}

/// MCP のサーバーのログ。リクエストのメソッド・エンドポイントと一致したか・ステータスコードだけを書き、本文とトークンは書かない (`.claude/rules/snippet-content-handling.md`)。
/// 埋め込みモデルの準備などメインアクターの外からも書くため、メインアクターに隔離しない (`Logger` は Sendable)。
nonisolated let mcpServerLogger = Logger(subsystem: "com.bannzai.tanzaku", category: "MCP")

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
        stateDidChange(
          mcpServerFailedState(error: error, port: port, isPortAcceptingConnections: isLoopbackPortAcceptingConnections(port: port))
        )
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
        let handlerTask = Task { @MainActor in
          let response = await handler(request)
          mcpServerLogger.info("\(mcpHTTPRequestLogText(request: request, statusCode: response.statusCode), privacy: .public)")
          sendMCPHTTPResponse(connection: connection, response: response)
        }
        cancelMCPHTTPHandlerWhenPeerCloses(connection: connection, handlerTask: handlerTask)
      }
    }
  }
}

/// 応答を返す前にクライアントが接続を閉じたら、リクエストの処理を取り消す。
///
/// 2026-07-28 の版は、依頼の取り消しを接続を閉じることで伝える (Streamable HTTP「Cancellation」)。確認待ちの削除の依頼を、取り消した後にユーザーが許可して消さないため。
/// 応答を返した後にこちらが接続を閉じた時も呼ばれるが、処理は終わっているため取り消しは何もしない。
private func cancelMCPHTTPHandlerWhenPeerCloses(connection: NWConnection, handlerTask: Task<Void, Never>) {
  connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { @Sendable _, _, isComplete, error in
    if isComplete || error != nil {
      handlerTask.cancel()
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
