/// 設定の「一般」の「前面のアプリに直接貼り付ける」を入れる `UserDefaults` のキー。設定画面 (#15) が書き込み、ランチャーは読むだけ。
let directPasteEnabledUserDefaultsKey = "directPasteEnabled"

/// ランチャーで選んだスニペットの出し方。
enum LauncherOutputAction: Equatable {
  /// クリップボードへコピーする。
  case copy
  /// クリップボードへコピーし、ランチャーを開く前に使っていたアプリへ ⌘V を送って貼り付ける。
  case copyAndPaste
}

/// ⌘Return で選んだ時の出し方。直接貼り付けは設定で許可し、アクセシビリティの許可 (⌘V のイベントを送るのに要る) もある時だけにし、それ以外はコピーだけにする (`documents/DIRECTION.md`「決めたこと」の直接貼り付けの行)。
func launcherCommandReturnAction(isDirectPasteEnabled: Bool, isAccessibilityTrusted: Bool) -> LauncherOutputAction {
  isDirectPasteEnabled && isAccessibilityTrusted ? .copyAndPaste : .copy
}
