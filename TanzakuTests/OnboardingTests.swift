import Foundation
import Testing

@testable import Tanzaku

/// 初回起動の手順の移り方と、終えた状態の保存を確かめる。
struct OnboardingTests {
  /// テストごとに別の `UserDefaults` を使い、アプリの設定と他のテストの値に触れないようにする。
  let userDefaults = UserDefaults(suiteName: "OnboardingTests-\(UUID().uuidString)")!

  @Test("「次へ」は手順を順に進め、最後の手順では初回起動を終える")
  func nextStep() {
    #expect(onboardingNextStep(step: .launcherShortcut) == .firstSnippet)
    #expect(onboardingNextStep(step: .firstSnippet) == .agentConnection)
    #expect(onboardingNextStep(step: .agentConnection) == nil)
  }

  @Test("「戻る」は 1 つ前の手順へ戻り、最初の手順では出さない")
  func previousStep() {
    #expect(onboardingPreviousStep(step: .launcherShortcut) == nil)
    #expect(onboardingPreviousStep(step: .firstSnippet) == .launcherShortcut)
    #expect(onboardingPreviousStep(step: .agentConnection) == .firstSnippet)
  }

  @Test("「スキップ」は AI エージェントの接続へ進み、そこでは初回起動を終える")
  func skipDestination() {
    #expect(onboardingSkipDestination(step: .launcherShortcut) == .agentConnection)
    #expect(onboardingSkipDestination(step: .firstSnippet) == .agentConnection)
    #expect(onboardingSkipDestination(step: .agentConnection) == nil)
  }

  @Test("初回起動を終えたことを保存すると、次に読んだ時も終えたままになる")
  func completionIsSaved() {
    #expect(!isOnboardingCompleted(userDefaults: userDefaults))
    markOnboardingCompleted(userDefaults: userDefaults)
    markOnboardingCompleted(userDefaults: userDefaults)
    #expect(isOnboardingCompleted(userDefaults: userDefaults))
  }
}
