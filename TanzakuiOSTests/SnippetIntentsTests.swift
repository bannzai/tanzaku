import AppIntents
import Testing

@testable import TanzakuiOS

/// ショートカット・Siri からスニペットを読む経路が、端末のロック解除を求めることを確かめる。
struct SnippetIntentsTests {
  @Test("スニペットをコピーする intent は実行にロック解除を求める")
  func copySnippetIntentRequiresAuthentication() {
    #expect(CopySnippetIntent.authenticationPolicy == .requiresAuthentication)
  }

  @Test("ロック中はスニペットを返さずエラーにする")
  func lockedDeviceThrows() {
    #expect(throws: SnippetIntentDeviceLockedError.self) {
      try requireUnlockedDeviceForSnippetIntent(isProtectedDataAvailable: false)
    }
  }

  @Test("ロックを解除していればエラーにしない")
  func unlockedDeviceDoesNotThrow() {
    #expect(throws: Never.self) {
      try requireUnlockedDeviceForSnippetIntent(isProtectedDataAvailable: true)
    }
  }
}
