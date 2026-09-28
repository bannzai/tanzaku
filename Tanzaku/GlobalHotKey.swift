import Carbon.HIToolbox
import os

/// グローバルショートカットの登録に失敗した時のエラー。`description` はそのまま表示・記録する。
struct GlobalHotKeyError: Error, CustomStringConvertible {
  /// 失敗した Carbon の関数名。
  var functionName: String
  /// Carbon が返した OSStatus。
  var status: OSStatus

  /// 表示・記録する文言。
  var description: String {
    "\(functionName) failed with OSStatus \(status)."
  }
}

/// ランチャーのショートカットの既定のキー (Space)。`documents/DIRECTION.md`「決めたこと」の既定 ⌥Space。変更は設定の「一般」(#15) で行う。
let launcherHotKeyCode = UInt32(kVK_Space)
/// ランチャーのショートカットの既定の修飾キー (⌥)。
let launcherHotKeyModifiers = UInt32(optionKey)

/// 登録したショートカットが押された時に呼ぶ処理。Carbon のイベントハンドラは値を捕まえられない C の関数ポインタのため、ここに置いて参照する。
private var globalHotKeyAction: (() -> Void)?
/// 登録したショートカット。2 回目の呼び出しで重ねて登録しないために持つ。
private var globalHotKeyRef: EventHotKeyRef?

/// グローバルショートカットを登録し、押された時に `action` を呼ぶ。
///
/// Carbon の `RegisterEventHotKey` を使う。アクセシビリティ・入力監視の許可が要らず、App Sandbox の中でも使えるため (ショートカットを受け取るだけで、ほかのキー入力は見ない)。
/// 登録はアプリの終了まで解除しない。登録済みなら `action` だけを差し替えて何もしないため、何度呼んでも登録は 1 つになる。
func registerGlobalHotKey(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) throws {
  globalHotKeyAction = action
  if globalHotKeyRef != nil {
    return
  }
  var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
  let installStatus = InstallEventHandler(
    GetApplicationEventTarget(),
    { _, _, _ in
      // アプリのイベントターゲットのハンドラはメインスレッドで呼ばれる。
      MainActor.assumeIsolated {
        globalHotKeyAction?()
      }
      return noErr
    },
    1,
    &eventType,
    nil,
    nil
  )
  guard installStatus == noErr else {
    throw GlobalHotKeyError(functionName: "InstallEventHandler", status: installStatus)
  }
  // 識別子はこのアプリで登録するショートカットが 1 つだけのため、区別に使わない固定の値にする。
  let hotKeyID = EventHotKeyID(signature: OSType(0x544E_5A4B), id: 1)
  var hotKeyRef: EventHotKeyRef?
  let registerStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
  guard registerStatus == noErr else {
    throw GlobalHotKeyError(functionName: "RegisterEventHotKey", status: registerStatus)
  }
  globalHotKeyRef = hotKeyRef
}
