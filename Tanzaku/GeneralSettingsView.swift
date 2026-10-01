import AppKit
import ApplicationServices
import Combine
import ServiceManagement
import SwiftUI

/// 設定の「一般」(`documents/design/Settings.dc.html` の tab=general)。ランチャーのショートカット・前面のアプリへの直接貼り付け・ログイン時の起動を扱う。
struct GeneralSettingsView: View {
  @Environment(LauncherShortcutController.self) private var launcherShortcutController
  /// ランチャーの ⌘Return で前面のアプリに貼り付けるか。ランチャーは押した時にこの値を読む (`LauncherPanelController`)。
  /// 既定はオフ。⌘V の送信は審査・誤操作の懸念があるため、ユーザーが許可した時だけにする (`documents/DIRECTION.md`「決めたこと」の直接貼り付けの行)。
  @AppStorage(directPasteEnabledUserDefaultsKey) private var isDirectPasteEnabled = false
  /// ⌘V を送る許可 (アクセシビリティとイベント送信) があるか。許可はシステム設定で変わり通知が無いため、アプリが前面に戻るたびに読み直す。
  @State private var isSyntheticKeyStrokePermissionGranted = isSyntheticKeyStrokeAllowed()
  /// ログイン項目の登録の状態。正はシステム (`SMAppService`) が持つため、保存せずに毎回読む。
  @State private var launchAtLoginStatus = SMAppService.mainApp.status
  /// ログイン項目の登録・解除の失敗。
  @State private var launchAtLoginErrorMessage: String?

  var body: some View {
    Form {
      Section {
        LabeledContent {
          LauncherShortcutRecorder()
        } label: {
          Text("Launcher shortcut")
          Text("Opens in the center of the screen from any app")
        }
        if let errorMessage = launcherShortcutController.errorMessage {
          Text(verbatim: errorMessage)
            .foregroundStyle(.red)
        }
      }

      Section {
        Toggle(isOn: $isDirectPasteEnabled) {
          Text("Paste directly into the front app")
          Text("⌘Return pastes into the app you were using before opening the launcher.")
        }
        if isDirectPasteEnabled && !isSyntheticKeyStrokePermissionGranted {
          HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
              .foregroundStyle(snippetBandColor(snippetColor: .yamabuki))
            VStack(alignment: .leading, spacing: 4) {
              Text("Accessibility permission hasn't been granted yet. Until you allow it, ⌘Return only copies.")
                .font(.callout)
              // 許可はアプリの署名ごとに記録され、署名の違うビルド (開発中のビルドと配布版など) に入れ替えると一覧にオンのまま残っても効かないため、外して載せ直す手順も書く。
              Text("Turn on Tanzaku in System Settings › Privacy & Security › Accessibility. If it's already on and this message stays, remove Tanzaku from the list with − and open System Settings again from here.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Open System Settings") {
              requestSyntheticKeyStrokeAccess()
            }
          }
          .accessibilityIdentifier("direct-paste-permission-guide")
        }
      }

      Section {
        Toggle(
          "Launch at login",
          isOn: Binding(
            get: { launchAtLoginStatus == .enabled || launchAtLoginStatus == .requiresApproval },
            set: { isEnabled in
              updateLaunchAtLogin(isEnabled: isEnabled)
            }
          )
        )
        if launchAtLoginStatus == .requiresApproval {
          HStack(spacing: 12) {
            Text("Allow Tanzaku in Login Items in System Settings to launch it at login.")
              .font(.callout)
              .frame(maxWidth: .infinity, alignment: .leading)
            Button("Open Login Items") {
              SMAppService.openSystemSettingsLoginItems()
            }
          }
        }
        if let launchAtLoginErrorMessage {
          Text(verbatim: launchAtLoginErrorMessage)
            .foregroundStyle(.red)
        }
      }
    }
    .formStyle(.grouped)
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      isSyntheticKeyStrokePermissionGranted = isSyntheticKeyStrokeAllowed()
      launchAtLoginStatus = SMAppService.mainApp.status
    }
  }

  /// ログイン項目に登録・解除し、システムの状態を読み直す。失敗したら理由を出し、トグルはシステムの状態のまま (変わらない) にする。
  private func updateLaunchAtLogin(isEnabled: Bool) {
    do {
      if isEnabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      launchAtLoginErrorMessage = nil
    } catch {
      launchAtLoginErrorMessage = error.localizedDescription
    }
    launchAtLoginStatus = SMAppService.mainApp.status
  }
}

/// ランチャーのショートカットの表示と記録 (デザインのショートカットの欄)。押すと次に押したキーを記録し、× でショートカットを消去する。
private struct LauncherShortcutRecorder: View {
  @Environment(LauncherShortcutController.self) private var launcherShortcutController

  var body: some View {
    HStack(spacing: 6) {
      Button {
        if launcherShortcutController.isRecording {
          launcherShortcutController.cancelRecording()
        } else {
          launcherShortcutController.startRecording()
        }
      } label: {
        HStack(spacing: 6) {
          if launcherShortcutController.isRecording {
            Text("Press the new shortcut")
              .foregroundStyle(.secondary)
          } else if let launcherShortcut = launcherShortcutController.launcherShortcut {
            ForEach(Array(launcherShortcutKeyLabels(launcherShortcut: launcherShortcut).enumerated()), id: \.offset) { _, label in
              ShortcutKeyCap(label: label, fontSize: 12, height: 20)
            }
          } else {
            Text("Record Shortcut")
              .foregroundStyle(.secondary)
          }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("launcherShortcutRecorder")
      if launcherShortcutController.launcherShortcut != nil && !launcherShortcutController.isRecording {
        Button {
          launcherShortcutController.clear()
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear Shortcut")
      }
    }
    .padding(.leading, 8)
    .padding(.trailing, 6)
    .frame(height: 28)
    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
    .onDisappear {
      launcherShortcutController.cancelRecording()
    }
  }
}
