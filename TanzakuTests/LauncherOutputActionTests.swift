import Foundation
import Testing

@testable import Tanzaku

/// ⌘Return の出し方が、設定とキー入力を送る許可の両方がある時だけ貼り付けになり、下の案内もその出し方に合わせることを確かめる。
struct LauncherOutputActionTests {
  @Test("直接貼り付けを許可し、キー入力を送る許可もある時だけ貼り付ける")
  func pasteRequiresSettingAndPermission() {
    #expect(launcherCommandReturnAction(isDirectPasteEnabled: true, isSyntheticKeyStrokeAllowed: true) == .copyAndPaste)
  }

  @Test("設定で許可していない時・キー入力を送る許可が無い時はコピーだけにする")
  func copyOnlyWithoutSettingOrPermission() {
    #expect(launcherCommandReturnAction(isDirectPasteEnabled: false, isSyntheticKeyStrokeAllowed: true) == .copy)
    #expect(launcherCommandReturnAction(isDirectPasteEnabled: true, isSyntheticKeyStrokeAllowed: false) == .copy)
    #expect(launcherCommandReturnAction(isDirectPasteEnabled: false, isSyntheticKeyStrokeAllowed: false) == .copy)
  }

  @Test("貼り付ける時だけ ⌘↩ の案内を「前面のアプリに貼り付け」にする")
  func hintLabelForPaste() {
    #expect(launcherCommandReturnHintLabel(action: .copyAndPaste).key == "Paste to the front app")
  }

  @Test("許可が無くコピーだけになる時は ⌘↩ の案内を「コピー」にする")
  func hintLabelForCopyWithoutPermission() {
    #expect(launcherCommandReturnHintLabel(action: launcherCommandReturnAction(isDirectPasteEnabled: true, isSyntheticKeyStrokeAllowed: false)).key == "Copy")
  }
}
