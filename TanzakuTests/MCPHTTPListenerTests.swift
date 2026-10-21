import Foundation
import Network
import Testing

@testable import Tanzaku

/// 待ち受けを始められなかった時の状態 (`mcpServerFailedState(error:port:isPortAcceptingConnections:)`) と、ポートへの接続の確認を確かめる。
struct MCPHTTPListenerTests {
  @Test("ほかのプロセスがポートで待ち受けている (EADDRINUSE で接続できる) 時は、ポートの使用中として警告する状態にする")
  func mapsAddressInUseWithListenerToPortInUse() {
    #expect(
      mcpServerFailedState(error: NWError.posix(.EADDRINUSE), port: 47831, isPortAcceptingConnections: true)
        == .portInUse(port: 47831)
    )
  }

  @Test("EADDRINUSE でも接続できない (自分の接続の TIME_WAIT など) 時は、警告せず失敗の状態にする")
  func mapsAddressInUseWithoutListenerToFailed() {
    let error = NWError.posix(.EADDRINUSE)
    #expect(
      mcpServerFailedState(error: error, port: 47831, isPortAcceptingConnections: false)
        == .failed(message: error.localizedDescription)
    )
  }

  @Test("ポートの使用中以外の失敗は、エラーの説明を持つ失敗の状態にする")
  func mapsOtherErrorsToFailed() {
    let error = NWError.posix(.EACCES)
    #expect(
      mcpServerFailedState(error: error, port: 47831, isPortAcceptingConnections: true)
        == .failed(message: error.localizedDescription)
    )
  }

  @Test("待ち受けているポートには接続でき、待ち受けを止めたポートには接続できない")
  func detectsLoopbackListener() throws {
    let listeningSocket = socket(AF_INET, SOCK_STREAM, 0)
    try #require(listeningSocket >= 0)
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = 0
    address.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)
    var addressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
    try withUnsafeMutablePointer(to: &address) { addressPointer in
      try addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        try #require(bind(listeningSocket, $0, addressLength) == 0)
        try #require(listen(listeningSocket, 1) == 0)
        try #require(getsockname(listeningSocket, $0, &addressLength) == 0)
      }
    }
    let port = Int(UInt16(bigEndian: address.sin_port))

    #expect(isLoopbackPortAcceptingConnections(port: port))
    close(listeningSocket)
    #expect(!isLoopbackPortAcceptingConnections(port: port))
  }
}
