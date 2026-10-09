import Foundation
import Testing

@testable import Tanzaku

/// タイトル・タグの自動の作成の設定の読み取りを確かめる。
struct SnippetMetadataGenerationTests {
  /// テストごとに別の `UserDefaults` を使い、アプリの設定と他のテストの値に触れないようにする。
  let userDefaults = UserDefaults(suiteName: "SnippetMetadataGenerationTests-\(UUID().uuidString)")!

  @Test("設定を変えていない時は、タイトルの自動の作成はオン、タグの自動の作成はオフ")
  func defaultsWithoutSavedValue() {
    #expect(isSnippetTitleGenerationEnabled(userDefaults: userDefaults))
    #expect(!isSnippetTagGenerationEnabled(userDefaults: userDefaults))
  }

  @Test("設定を変えると、変えた値を読む")
  func readsSavedValue() {
    userDefaults.set(false, forKey: snippetTitleGenerationEnabledUserDefaultsKey)
    userDefaults.set(true, forKey: snippetTagGenerationEnabledUserDefaultsKey)

    #expect(!isSnippetTitleGenerationEnabled(userDefaults: userDefaults))
    #expect(isSnippetTagGenerationEnabled(userDefaults: userDefaults))
  }
}
