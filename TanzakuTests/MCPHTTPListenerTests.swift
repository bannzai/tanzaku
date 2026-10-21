import Foundation
import Network
import Testing

@testable import Tanzaku

/// 待ち受けを始められなかった時の状態 (`mcpServerFailedState(error:port:)`) を、Network framework が返すエラーで確かめる。
struct MCPHTTPListenerTests {
  @Test("ほかのプロセスがポートを使っている (EADDRINUSE) 時は、ポートの使用中として警告する状態にする")
  func mapsAddressInUseToPortInUse() {
    #expect(mcpServerFailedState(error: NWError.posix(.EADDRINUSE), port: 47831) == .portInUse(port: 47831))
  }

  @Test("ポートの使用中以外の失敗は、エラーの説明を持つ失敗の状態にする")
  func mapsOtherErrorsToFailed() {
    let error = NWError.posix(.EACCES)
    #expect(mcpServerFailedState(error: error, port: 47831) == .failed(message: error.localizedDescription))
  }
}
