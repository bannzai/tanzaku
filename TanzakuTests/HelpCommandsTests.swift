import Foundation
import Testing

@testable import Tanzaku

/// ヘルプのメニューのお問い合わせと法務ドキュメントの URL を確かめる。
struct HelpCommandsTests {
  @Test("法務ドキュメントは日本語なら日本語版、それ以外は英語版を開く")
  func legalDocumentLanguage() {
    #expect(legalDocumentURL(legalDocument: .terms, languageCode: "ja")?.absoluteString == "https://bannzai.github.io/tanzaku/Terms-ja")
    #expect(legalDocumentURL(legalDocument: .terms, languageCode: "en")?.absoluteString == "https://bannzai.github.io/tanzaku/Terms-en")
    #expect(legalDocumentURL(legalDocument: .privacyPolicy, languageCode: "ja")?.absoluteString == "https://bannzai.github.io/tanzaku/PrivacyPolicy-ja")
    #expect(legalDocumentURL(legalDocument: .privacyPolicy, languageCode: nil)?.absoluteString == "https://bannzai.github.io/tanzaku/PrivacyPolicy-en")
  }

  @Test("特定商取引法に基づく表記は日本語版しか無いため、どの言語でも日本語版を開く")
  func specifiedCommercialTransactionActIsJapaneseOnly() {
    #expect(
      legalDocumentURL(legalDocument: .specifiedCommercialTransactionAct, languageCode: "en")?.absoluteString
        == "https://bannzai.github.io/tanzaku/SpecifiedCommercialTransactionAct-ja"
    )
  }

  @Test("お問い合わせのメールは宛先・件名と、本文にアプリと macOS の版を入れる")
  func contactMail() throws {
    let url = try #require(contactMailURL(subject: "Tanzaku へのお問い合わせ", appVersion: "0.1.0", buildNumber: "7", osVersion: "15.1.0"))
    let urlComponents = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(urlComponents.scheme == "mailto")
    #expect(urlComponents.path == "bannzai.app@gmail.com")
    #expect(urlComponents.queryItems?.first(where: { $0.name == "subject" })?.value == "Tanzaku へのお問い合わせ")
    #expect(urlComponents.queryItems?.first(where: { $0.name == "body" })?.value == "\n\n---\nTanzaku 0.1.0 (7)\nmacOS 15.1.0")
  }
}
