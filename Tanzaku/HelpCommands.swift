import AppKit
import SwiftUI

/// お問い合わせの宛先。公開サイトと法務ドキュメント (`docs/`) に載せている連絡先と同じ。
let supportEmailAddress = "bannzai.app@gmail.com"
/// 法務ドキュメントを配信する GitHub Pages (`docs/`) の URL。`fastlane/metadata/*/marketing_url.txt` と同じ。
let publicSiteBaseURL = "https://bannzai.github.io/tanzaku/"

/// ヘルプのメニューから開く法務ドキュメント。
enum LegalDocument {
  /// 利用規約。
  case terms
  /// プライバシーポリシー。
  case privacyPolicy
  /// 特定商取引法に基づく表記。
  case specifiedCommercialTransactionAct
}

/// 法務ドキュメントの URL。`languageCode` が日本語なら日本語版、それ以外は英語版にする。
///
/// 特定商取引法に基づく表記は日本の法律の表記で、日本語版しか置いていないため、どの言語でも日本語版にする。
func legalDocumentURL(legalDocument: LegalDocument, languageCode: String?) -> URL? {
  let languageSuffix = languageCode == "ja" ? "ja" : "en"
  return switch legalDocument {
  case .terms:
    URL(string: "\(publicSiteBaseURL)Terms-\(languageSuffix)")
  case .privacyPolicy:
    URL(string: "\(publicSiteBaseURL)PrivacyPolicy-\(languageSuffix)")
  case .specifiedCommercialTransactionAct:
    URL(string: "\(publicSiteBaseURL)SpecifiedCommercialTransactionAct-ja")
  }
}

/// お問い合わせのメールを作る `mailto:` の URL。本文の末尾にアプリと macOS の版を入れ、問い合わせを受けた時にどの版の不具合かを分かるようにする。
func contactMailURL(subject: String, appVersion: String, buildNumber: String, osVersion: String) -> URL? {
  var urlComponents = URLComponents()
  urlComponents.scheme = "mailto"
  urlComponents.path = supportEmailAddress
  urlComponents.queryItems = [
    URLQueryItem(name: "subject", value: subject),
    URLQueryItem(name: "body", value: "\n\n---\nTanzaku \(appVersion) (\(buildNumber))\nmacOS \(osVersion)"),
  ]
  return urlComponents.url
}

/// ヘルプのメニュー。お問い合わせと法務ドキュメントへのリンクを置く。アプリにヘルプのドキュメントは無いため、既定の「Tanzaku ヘルプ」の項目と置き換える。
struct HelpCommands: Commands {
  var body: some Commands {
    CommandGroup(replacing: .help) {
      Button("Contact Us…") {
        let bundle = Bundle.main
        let operatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
        // 版はビルドの設定 (MARKETING_VERSION・CURRENT_PROJECT_VERSION) が必ず Info.plist に入れる。読めない時も版を空にしてお問い合わせは送れるようにする。
        guard
          let url = contactMailURL(
            subject: String(localized: "Tanzaku Inquiry"),
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            osVersion: "\(operatingSystemVersion.majorVersion).\(operatingSystemVersion.minorVersion).\(operatingSystemVersion.patchVersion)"
          )
        else {
          return
        }
        NSWorkspace.shared.open(url)
      }
      Divider()
      Button("Terms of Use") {
        openLegalDocument(legalDocument: .terms)
      }
      Button("Privacy Policy") {
        openLegalDocument(legalDocument: .privacyPolicy)
      }
      Button("Specified Commercial Transactions Act") {
        openLegalDocument(legalDocument: .specifiedCommercialTransactionAct)
      }
    }
  }
}

/// 法務ドキュメントをブラウザで開く。言語はアプリの表示の言語に合わせる。
private func openLegalDocument(legalDocument: LegalDocument) {
  guard let url = legalDocumentURL(legalDocument: legalDocument, languageCode: Bundle.main.preferredLocalizations.first) else {
    return
  }
  NSWorkspace.shared.open(url)
}
