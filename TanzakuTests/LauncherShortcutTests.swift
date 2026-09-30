import AppKit
import Carbon.HIToolbox
import Foundation
import Testing

@testable import Tanzaku

/// ランチャーのショートカットの保存・記録・表示を確かめる。
struct LauncherShortcutTests {
  /// テストごとに別の `UserDefaults` を使い、アプリの設定と他のテストの値に触れないようにする。
  let userDefaults = UserDefaults(suiteName: "LauncherShortcutTests-\(UUID().uuidString)")!

  @Test("保存が無い時は既定の ⌥Space を読む")
  func defaultShortcutWithoutSavedValue() {
    #expect(loadLauncherShortcut(userDefaults: userDefaults) == LauncherShortcut(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(optionKey)))
  }

  @Test("変えたショートカットを保存すると、次に読んだ時もそのショートカットになる")
  func savedShortcutIsLoaded() throws {
    let launcherShortcut = LauncherShortcut(keyCode: UInt32(kVK_ANSI_K), carbonModifiers: UInt32(cmdKey | shiftKey))
    try saveLauncherShortcut(launcherShortcut: launcherShortcut, userDefaults: userDefaults)
    #expect(loadLauncherShortcut(userDefaults: userDefaults) == launcherShortcut)
  }

  @Test("消去を保存すると、既定に戻らず nil を読む")
  func clearedShortcutStaysCleared() throws {
    try saveLauncherShortcut(launcherShortcut: nil, userDefaults: userDefaults)
    #expect(loadLauncherShortcut(userDefaults: userDefaults) == nil)
  }

  @Test("読めない値が入っている時は既定の ⌥Space を読む")
  func brokenValueFallsBackToDefault() {
    userDefaults.set(Data("broken".utf8), forKey: launcherShortcutUserDefaultsKey)
    #expect(loadLauncherShortcut(userDefaults: userDefaults) == defaultLauncherShortcut)
  }

  @Test("NSEvent の修飾キーを Carbon の修飾キーに変え、Caps Lock は含めない")
  func carbonModifiersFromModifierFlags() {
    #expect(carbonModifiers(modifierFlags: [.command, .option, .control, .shift, .capsLock]) == UInt32(cmdKey | optionKey | controlKey | shiftKey))
    #expect(carbonModifiers(modifierFlags: [.option]) == UInt32(optionKey))
    #expect(carbonModifiers(modifierFlags: []) == 0)
  }

  @Test("⌘・⌥・⌃ のどれかを押したキーだけをショートカットとして記録する")
  func recordingRequiresModifier() {
    #expect(recordedLauncherShortcut(keyCode: UInt16(kVK_Space), modifierFlags: [.control]) == LauncherShortcut(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(controlKey)))
    #expect(recordedLauncherShortcut(keyCode: UInt16(kVK_ANSI_A), modifierFlags: []) == nil)
    #expect(recordedLauncherShortcut(keyCode: UInt16(kVK_ANSI_A), modifierFlags: [.shift]) == nil)
  }

  @Test("キーキャップは修飾キーを ⌃⌥⇧⌘ の順に並べ、最後にキーの名前を置く")
  func keyLabelsOrder() {
    #expect(launcherShortcutKeyLabels(launcherShortcut: defaultLauncherShortcut) == ["⌥", "Space"])
    #expect(
      launcherShortcutKeyLabels(launcherShortcut: LauncherShortcut(keyCode: UInt32(kVK_F5), carbonModifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey)))
        == ["⌃", "⌥", "⇧", "⌘", "F5"]
    )
  }
}
