import Foundation

/// 設定の「一般」の「前面のアプリに直接貼り付ける」を入れる `UserDefaults` のキー。設定の「一般」(`GeneralSettingsView`) が書き込み、ランチャーは読むだけ。
let directPasteEnabledUserDefaultsKey = "directPasteEnabled"

/// ランチャーで選んだスニペットの出し方。
enum LauncherOutputAction: Equatable {
  /// クリップボードへコピーする。
  case copy
  /// クリップボードへコピーし、ランチャーを開く前に使っていたアプリへ ⌘V を送って貼り付ける。
  case copyAndPaste
}

/// ⌘Return で選んだ時の出し方。直接貼り付けは設定で許可し、⌘V のイベントを送る許可 (`isSyntheticKeyStrokeAllowed()`) もある時だけにし、それ以外はコピーだけにする (`documents/DIRECTION.md`「決めたこと」の直接貼り付けの行)。
func launcherCommandReturnAction(isDirectPasteEnabled: Bool, isSyntheticKeyStrokeAllowed: Bool) -> LauncherOutputAction {
  isDirectPasteEnabled && isSyntheticKeyStrokeAllowed ? .copyAndPaste : .copy
}

/// ランチャーの下の案内で ⌘↩ の後に出す操作の名前。許可が無くコピーだけになる時に「貼り付け」と出すと、押しても貼り付かない理由が分からないため、実際の出し方に合わせる。
func launcherCommandReturnHintLabel(action: LauncherOutputAction) -> LocalizedStringResource {
  switch action {
  case .copy:
    "Copy"
  case .copyAndPaste:
    "Paste to the front app"
  }
}
