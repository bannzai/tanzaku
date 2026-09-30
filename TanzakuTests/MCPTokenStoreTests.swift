import Foundation
import Testing

@testable import Tanzaku

/// アクセストークンの作成・再発行・照合を、メモリの保管場所で確かめる。
struct MCPTokenStoreTests {
  @Test("持ち主のいないトークンは、再発行するまで同じものを返す")
  func unboundTokenIsStableUntilReissued() throws {
    let tokenStore = inMemoryMCPTokenStore()

    let firstToken = try mcpUnboundToken(tokenStore: tokenStore)
    let secondToken = try mcpUnboundToken(tokenStore: tokenStore)
    let reissuedToken = try reissueMCPUnboundToken(tokenStore: tokenStore)

    #expect(firstToken == secondToken)
    #expect(reissuedToken != firstToken)
    #expect(try mcpUnboundToken(tokenStore: tokenStore) == reissuedToken)
  }

  @Test("トークンは URL で使える Base64 の 43 文字 (256 ビット) で、毎回違う")
  func accessTokenFormat() {
    let token = makeMCPAccessToken()

    #expect(token.count == 43)
    #expect(token.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    #expect(makeMCPAccessToken() != token)
  }

  @Test("Authorization ヘッダーの Bearer トークンが一致した持ち主を返す")
  func findsTokenOwner() {
    let clientID = UUID()
    let tokens: [MCPTokenOwner: String] = [.unbound: "dummy-token-unbound", .client(id: clientID): "dummy-token-client"]

    #expect(mcpTokenOwner(authorizationHeader: "Bearer dummy-token-client", tokens: tokens) == .client(id: clientID))
    #expect(mcpTokenOwner(authorizationHeader: "bearer dummy-token-unbound", tokens: tokens) == .unbound)
    #expect(mcpTokenOwner(authorizationHeader: "Bearer dummy-token-client-x", tokens: tokens) == nil)
    #expect(mcpTokenOwner(authorizationHeader: "Basic dummy-token-client", tokens: tokens) == nil)
    #expect(mcpTokenOwner(authorizationHeader: nil, tokens: tokens) == nil)
  }
}
