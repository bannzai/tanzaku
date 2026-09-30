import Foundation

/// 初回起動の手順 (`documents/design/Onboarding.dc.html`)。値はデザインの手順の番号。
enum OnboardingStep: Int, CaseIterable {
  /// ランチャーを開くキー。
  case launcherShortcut = 1
  /// 最初のスニペット。
  case firstSnippet
  /// AI エージェントの接続。
  case agentConnection
}

/// 初回起動を終えたかを入れる `UserDefaults` のキー。終えたら次の起動から初回起動を出さない。
let onboardingCompletedUserDefaultsKey = "onboardingCompleted"

/// 「次へ」の行き先。最後の手順では `nil` (初回起動を終える)。
func onboardingNextStep(step: OnboardingStep) -> OnboardingStep? {
  OnboardingStep(rawValue: step.rawValue + 1)
}

/// 「戻る」の行き先。最初の手順では `nil` (「戻る」を出さない)。
func onboardingPreviousStep(step: OnboardingStep) -> OnboardingStep? {
  OnboardingStep(rawValue: step.rawValue - 1)
}

/// 「スキップ」の行き先。最後の手順より前は最後の手順 (AI エージェントの接続) へ進め、最後の手順では `nil` (初回起動を終える)。
///
/// デザインのスキップは最後の手順へ進む。AI エージェントの接続は設定からいつでもできることを最後の手順で伝えるため。
func onboardingSkipDestination(step: OnboardingStep) -> OnboardingStep? {
  step == .agentConnection ? nil : .agentConnection
}

/// 初回起動を終えたか。
func isOnboardingCompleted(userDefaults: UserDefaults) -> Bool {
  userDefaults.bool(forKey: onboardingCompletedUserDefaultsKey)
}

/// 初回起動を終えたことを保存する。何度呼んでも同じ状態になる。
func markOnboardingCompleted(userDefaults: UserDefaults) {
  userDefaults.set(true, forKey: onboardingCompletedUserDefaultsKey)
}
