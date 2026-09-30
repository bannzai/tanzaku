import Foundation
import Testing

@testable import Tanzaku

/// Sparkle が読む更新の設定 (Info.plist) がアプリに入っていることを確かめる。ユニットテストはこのアプリを起動して走るため、`Bundle.main` はアプリの bundle になる。
struct UpdateCommandsTests {
  @Test("appcast の URL は docs/ の GitHub Pages の appcast.xml を指す")
  func feedURL() {
    #expect(Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String == "\(publicSiteBaseURL)appcast.xml")
  }

  @Test("更新の署名を確かめる公開鍵は EdDSA (ed25519) の 32 バイトの鍵")
  func publicEDKey() throws {
    let publicEDKey = try #require(Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)
    #expect(Data(base64Encoded: publicEDKey)?.count == 32)
  }

  @Test("自動の確認をオンにして、Sparkle が 2 回目の起動で出す許可のダイアログを出さない")
  func automaticChecksEnabled() {
    #expect(Bundle.main.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool == true)
  }

  @Test("Sparkle が比べる CFBundleVersion は表示の版 (CFBundleShortVersionString) と同じ")
  func bundleVersionMatchesShortVersion() throws {
    let shortVersion = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
    #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String == shortVersion)
  }
}
