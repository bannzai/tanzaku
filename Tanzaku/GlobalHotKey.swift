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

/// 登録したショートカットが押された時に呼ぶ処理。Carbon のイベントハンドラは値を捕まえられない C の関数ポインタのため、ここに置いて参照する。
private var globalHotKeyAction: (() -> Void)?
/// 登録したショートカット。登録し直す時に前のものを解除するために持つ。
private var globalHotKeyRef: EventHotKeyRef?
/// ショートカットが押されたイベントを受け取るハンドラを入れたか。ハンドラはアプリの終了まで 1 つだけ入れる。
private var isGlobalHotKeyHandlerInstalled = false

/// 前に登録したグローバルショートカットを解除し、`launcherShortcut` を登録し直す。押された時に `action` を呼ぶ。`launcherShortcut` が `nil` なら解除だけする。
///
/// Carbon の `RegisterEventHotKey` を使う。アクセシビリティ・入力監視の許可が要らず、App Sandbox の中でも使えるため (ショートカットを受け取るだけで、ほかのキー入力は見ない)。
/// 同じ引数で何度呼んでも、登録は `launcherShortcut` の 1 つになる。登録に失敗した時は何も登録していない状態で throw する。
func registerGlobalHotKey(launcherShortcut: LauncherShortcut?, action: @escaping () -> Void) throws {
  globalHotKeyAction = action
  if !isGlobalHotKeyHandlerInstalled {
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
    isGlobalHotKeyHandlerInstalled = true
  }
  if let registeredHotKeyRef = globalHotKeyRef {
    UnregisterEventHotKey(registeredHotKeyRef)
    globalHotKeyRef = nil
  }
  guard let launcherShortcut else {
    return
  }
  // 識別子はこのアプリで登録するショートカットが 1 つだけのため、区別に使わない固定の値にする。
  let hotKeyID = EventHotKeyID(signature: OSType(0x544E_5A4B), id: 1)
  var hotKeyRef: EventHotKeyRef?
  let registerStatus = RegisterEventHotKey(
    launcherShortcut.keyCode,
    launcherShortcut.carbonModifiers,
    hotKeyID,
    GetApplicationEventTarget(),
    0,
    &hotKeyRef
  )
  guard registerStatus == noErr else {
    throw GlobalHotKeyError(functionName: "RegisterEventHotKey", status: registerStatus)
  }
  globalHotKeyRef = hotKeyRef
}
