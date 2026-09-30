import Combine
import Sparkle
import SwiftUI

/// アプリのメニューの「アップデートを確認…」。Sparkle の標準の画面で新しい版を確かめる。
///
/// appcast の URL と公開鍵は Info.plist (`Tanzaku/Info.plist`) の `SUFeedURL`・`SUPublicEDKey` に置き、Sparkle が読む。
struct UpdateCommands: Commands {
  /// 更新を確かめる Sparkle の updater。
  let updater: SPUUpdater

  var body: some Commands {
    CommandGroup(after: .appInfo) {
      CheckForUpdatesButton(updater: updater)
    }
  }
}

/// 「アップデートを確認…」のボタン。確認中など Sparkle が確認を受け付けない間は押せなくする。
private struct CheckForUpdatesButton: View {
  /// 更新を確かめる Sparkle の updater。
  private let updater: SPUUpdater
  /// Sparkle が確認を受け付けるか。
  @ObservedObject private var updaterState: UpdaterState

  /// `updaterState` を `updater` から作るため、memberwise initializer ではなく自前で書く (Sparkle の SwiftUI の例と同じ形 https://sparkle-project.org/documentation/programmatic-setup/ )。
  init(updater: SPUUpdater) {
    self.updater = updater
    updaterState = UpdaterState(updater: updater)
  }

  var body: some View {
    Button("Check for Updates…") {
      updater.checkForUpdates()
    }
    .disabled(!updaterState.canCheckForUpdates)
  }
}

/// Sparkle の `canCheckForUpdates` を SwiftUI に渡す。`SPUUpdater` は KVO でしか変化を知らせないため、`ObservableObject` で受ける。
private final class UpdaterState: ObservableObject {
  /// Sparkle が確認を受け付けるか。
  @Published var canCheckForUpdates = false

  /// `updater` の `canCheckForUpdates` を追い始める。
  init(updater: SPUUpdater) {
    updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
  }
}
