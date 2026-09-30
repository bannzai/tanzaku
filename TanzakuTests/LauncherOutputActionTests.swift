import Testing

@testable import Tanzaku

/// ⌘Return の出し方が、設定とアクセシビリティの許可の両方がある時だけ貼り付けになることを確かめる。
struct LauncherOutputActionTests {
  @Test("直接貼り付けを許可し、アクセシビリティの許可もある時だけ貼り付ける")
  func pasteRequiresSettingAndAccessibility() {
    #expect(launcherCommandReturnAction(isDirectPasteEnabled: true, isAccessibilityTrusted: true) == .copyAndPaste)
  }

  @Test("設定で許可していない時・アクセシビリティの許可が無い時はコピーだけにする")
  func copyOnlyWithoutSettingOrAccessibility() {
    #expect(launcherCommandReturnAction(isDirectPasteEnabled: false, isAccessibilityTrusted: true) == .copy)
    #expect(launcherCommandReturnAction(isDirectPasteEnabled: true, isAccessibilityTrusted: false) == .copy)
    #expect(launcherCommandReturnAction(isDirectPasteEnabled: false, isAccessibilityTrusted: false) == .copy)
  }
}
