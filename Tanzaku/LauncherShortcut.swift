import AppKit
import Carbon.HIToolbox

/// ランチャーを開くグローバルショートカット。Carbon の `RegisterEventHotKey` にそのまま渡す値で持つ。
struct LauncherShortcut: Codable, Equatable {
  /// 仮想キーコード (`kVK_*`)。
  var keyCode: UInt32
  /// Carbon の修飾キー (`cmdKey`・`optionKey`・`controlKey`・`shiftKey` の和)。
  var carbonModifiers: UInt32
}

/// ランチャーのショートカットの既定の ⌥Space。`documents/DIRECTION.md`「決めたこと」の設定の「一般」の行。
let defaultLauncherShortcut = LauncherShortcut(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(optionKey))

/// 設定の「一般」で変えたランチャーのショートカットを入れる `UserDefaults` のキー。値は `LauncherShortcut?` の JSON で、消去した時は `null` を入れる。
let launcherShortcutUserDefaultsKey = "launcherShortcut"

/// 保存したランチャーのショートカットを読む。設定で消去した時は `nil`。
///
/// 保存が無い (一度も変えていない) 時と、読めない値が入っている時は既定の ⌥Space にする。読めない値のままショートカットを無くすと、ランチャーを開く手段が無くなるため。
func loadLauncherShortcut(userDefaults: UserDefaults) -> LauncherShortcut? {
  guard let data = userDefaults.data(forKey: launcherShortcutUserDefaultsKey) else {
    return defaultLauncherShortcut
  }
  do {
    return try JSONDecoder().decode(LauncherShortcut?.self, from: data)
  } catch {
    return defaultLauncherShortcut
  }
}

/// ランチャーのショートカットを保存する。`nil` は消去として保存し、次の起動でも既定の ⌥Space に戻さない。
func saveLauncherShortcut(launcherShortcut: LauncherShortcut?, userDefaults: UserDefaults) throws {
  userDefaults.set(try JSONEncoder().encode(launcherShortcut), forKey: launcherShortcutUserDefaultsKey)
}

/// `NSEvent` の修飾キーを Carbon の修飾キーに変える。ショートカットの判定に使わない Caps Lock・Fn は含めない。
func carbonModifiers(modifierFlags: NSEvent.ModifierFlags) -> UInt32 {
  ([
    (.command, cmdKey),
    (.option, optionKey),
    (.control, controlKey),
    (.shift, shiftKey),
  ] as [(NSEvent.ModifierFlags, Int)])
  .filter { modifierFlags.contains($0.0) }
  .reduce(UInt32(0)) { $0 | UInt32($1.1) }
}

/// 記録したキーからランチャーのショートカットを作る。⌘・⌥・⌃ のどれも押していなければ `nil`。
///
/// 修飾キーなしや ⇧ だけのキーをグローバルショートカットにすると、ほかのアプリでその文字を打てなくなるため。
func recordedLauncherShortcut(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> LauncherShortcut? {
  guard !modifierFlags.intersection([.command, .option, .control]).isEmpty else {
    return nil
  }
  return LauncherShortcut(keyCode: UInt32(keyCode), carbonModifiers: carbonModifiers(modifierFlags: modifierFlags))
}

/// ショートカットのキーキャップに出す文字。修飾キーを macOS のメニューと同じ ⌃⌥⇧⌘ の順に並べ、最後にキーの名前を置く。
func launcherShortcutKeyLabels(launcherShortcut: LauncherShortcut) -> [String] {
  ([
    (controlKey, "⌃"),
    (optionKey, "⌥"),
    (shiftKey, "⇧"),
    (cmdKey, "⌘"),
  ] as [(Int, String)])
  .filter { launcherShortcut.carbonModifiers & UInt32($0.0) != 0 }
  .map { $0.1 } + [launcherShortcutKeyName(keyCode: launcherShortcut.keyCode)]
}

/// キーの名前。文字を入力しないキーは記号か英語の名前にし、それ以外は今のキーボード配列でそのキーが入力する文字の大文字にする。
func launcherShortcutKeyName(keyCode: UInt32) -> String {
  if let specialKeyName = specialKeyNames[Int(keyCode)] {
    return specialKeyName
  }
  // キーボード配列から文字を取れないキーは、別のキーと見分けられるようキーコードを出す。
  return keyboardLayoutCharacter(keyCode: keyCode) ?? "#\(keyCode)"
}

/// 文字を入力しないキーの名前。Space はデザイン (`documents/design/Settings.dc.html`) の表記。
private let specialKeyNames: [Int: String] = [
  kVK_Space: "Space",
  kVK_Return: "↩",
  kVK_ANSI_KeypadEnter: "⌤",
  kVK_Tab: "⇥",
  kVK_Delete: "⌫",
  kVK_ForwardDelete: "⌦",
  kVK_Escape: "⎋",
  kVK_LeftArrow: "←",
  kVK_RightArrow: "→",
  kVK_UpArrow: "↑",
  kVK_DownArrow: "↓",
  kVK_Home: "↖",
  kVK_End: "↘",
  kVK_PageUp: "⇞",
  kVK_PageDown: "⇟",
  kVK_F1: "F1",
  kVK_F2: "F2",
  kVK_F3: "F3",
  kVK_F4: "F4",
  kVK_F5: "F5",
  kVK_F6: "F6",
  kVK_F7: "F7",
  kVK_F8: "F8",
  kVK_F9: "F9",
  kVK_F10: "F10",
  kVK_F11: "F11",
  kVK_F12: "F12",
  kVK_F13: "F13",
  kVK_F14: "F14",
  kVK_F15: "F15",
  kVK_F16: "F16",
  kVK_F17: "F17",
  kVK_F18: "F18",
  kVK_F19: "F19",
  kVK_F20: "F20",
]

/// 今の ASCII のキーボード配列で、修飾キーなしにそのキーが入力する文字の大文字。取れなければ `nil`。
///
/// 日本語入力の最中でもローマ字の文字で出すため、ASCII を入力できる配列を使う。
private func keyboardLayoutCharacter(keyCode: UInt32) -> String? {
  guard let inputSource = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
    let layoutDataPointer = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData)
  else {
    return nil
  }
  let layoutData = Unmanaged<CFData>.fromOpaque(layoutDataPointer).takeUnretainedValue() as Data
  var deadKeyState: UInt32 = 0
  var characters = [UniChar](repeating: 0, count: 4)
  var length = 0
  let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
    guard let keyboardLayout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
      return OSStatus(paramErr)
    }
    return UCKeyTranslate(
      keyboardLayout,
      UInt16(keyCode),
      UInt16(kUCKeyActionDisplay),
      0,
      UInt32(LMGetKbdType()),
      OptionBits(kUCKeyTranslateNoDeadKeysBit),
      &deadKeyState,
      characters.count,
      &length,
      &characters
    )
  }
  guard status == noErr, length > 0 else {
    return nil
  }
  return String(utf16CodeUnits: characters, count: length).uppercased()
}
