import AppKit
import Carbon.HIToolbox
import SwiftUI

/// ランチャーのショートカットの登録・変更・記録の状態。
///
/// 設定の「一般」と初回起動の 1 つ目の手順が同じショートカットを見て変えるため、SwiftUI が変更を追える `@Observable` のクラスにする。
@Observable
final class LauncherShortcutController {
  /// 登録しているショートカット。設定で消去した時は `nil`。
  private(set) var launcherShortcut: LauncherShortcut?
  /// 登録・保存の失敗。設定と初回起動に表示する。
  private(set) var errorMessage: String?
  /// 次に押したキーをショートカットとして記録しているか。
  private(set) var isRecording = false

  /// ショートカットを保存する場所。
  @ObservationIgnored private let userDefaults: UserDefaults
  /// ショートカットが押された時に呼ぶ処理。`start(action:)` で入れる。
  @ObservationIgnored private var action: (() -> Void)?
  /// 記録中のキー入力の監視。記録していない時は `nil`。
  @ObservationIgnored private var recordingMonitor: Any?

  /// 保存したショートカットを読む。登録は `start(action:)` で行う。
  ///
  /// 設定のウィンドウの scene が `applicationDidFinishLaunching` より先に読んでも同じ値を出せるよう、登録と分けて delegate を作る時に読む。
  init(userDefaults: UserDefaults) {
    self.userDefaults = userDefaults
    launcherShortcut = loadLauncherShortcut(userDefaults: userDefaults)
  }

  /// 保存したショートカットを登録し、押された時に `action` を呼ぶ。何度呼んでも登録は 1 つになる。
  func start(action: @escaping () -> Void) {
    self.action = action
    do {
      try registerGlobalHotKey(launcherShortcut: launcherShortcut, action: action)
      errorMessage = nil
    } catch {
      errorMessage = "\(error)"
    }
  }

  /// 次に押したキーを記録し始める。記録中なら何もしない。
  ///
  /// 記録の間は今のショートカットを解除する。解除しないと、今と同じキーを押した時に Carbon が先に受け取ってランチャーが開き、記録できないため。
  func startRecording() {
    guard !isRecording else {
      return
    }
    isRecording = true
    try? registerGlobalHotKey(launcherShortcut: nil, action: action ?? {})
    recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      self?.record(event: event)
      return nil
    }
  }

  /// 記録をやめ、今のショートカットを登録し直す。記録していなければ何もしない。
  func cancelRecording() {
    guard isRecording else {
      return
    }
    finishRecording()
    start(action: action ?? {})
  }

  /// ショートカットを消去する。ランチャーはショートカットで開かなくなる。
  func clear() {
    finishRecording()
    apply(launcherShortcut: nil)
  }

  /// 記録中に押されたキーを処理する。Esc は記録の取り消し、⌘・⌥・⌃ を含むキーは新しいショートカット、それ以外は警告音を鳴らして記録を続ける。
  private func record(event: NSEvent) {
    if Int(event.keyCode) == kVK_Escape && event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
      cancelRecording()
      return
    }
    guard let recordedShortcut = recordedLauncherShortcut(keyCode: event.keyCode, modifierFlags: event.modifierFlags) else {
      NSSound.beep()
      return
    }
    finishRecording()
    apply(launcherShortcut: recordedShortcut)
  }

  /// 記録のキー入力の監視を外す。
  private func finishRecording() {
    if let recordingMonitor {
      NSEvent.removeMonitor(recordingMonitor)
    }
    recordingMonitor = nil
    isRecording = false
  }

  /// `newShortcut` を登録して保存する。登録できなければ (ほかのアプリが同じキーを使っている等) 前のショートカットを登録し直し、保存しない。
  private func apply(launcherShortcut newShortcut: LauncherShortcut?) {
    let registrationAction = action ?? {}
    do {
      try registerGlobalHotKey(launcherShortcut: newShortcut, action: registrationAction)
      try saveLauncherShortcut(launcherShortcut: newShortcut, userDefaults: userDefaults)
      launcherShortcut = newShortcut
      errorMessage = nil
    } catch {
      try? registerGlobalHotKey(launcherShortcut: launcherShortcut, action: registrationAction)
      errorMessage = String(localized: "Couldn't use this shortcut: \(String(describing: error))")
    }
  }
}

/// ショートカットの 1 つのキーのキーキャップ。設定の「一般」は小さく、初回起動の 1 つ目の手順は大きく出す (`documents/design/Settings.dc.html`・`documents/design/Onboarding.dc.html`)。
struct ShortcutKeyCap: View {
  /// キーの記号か名前。
  let label: String
  /// 文字の大きさ。
  let fontSize: CGFloat
  /// キーキャップの高さ。
  let height: CGFloat

  var body: some View {
    Text(verbatim: label)
      .font(.system(size: fontSize))
      .padding(.horizontal, height / 3)
      .frame(minWidth: height, minHeight: height)
      .overlay(RoundedRectangle(cornerRadius: height / 5).strokeBorder(.tertiary))
  }
}
