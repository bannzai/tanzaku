import SwiftUI

/// iOS アプリのエントリポイント。本体の画面 (一覧・検索・編集) は iOS 本体アプリの issue で作るため、この段階は起動できる最小の画面だけを持つ。
@main
struct TanzakuiOSApp: App {
  var body: some Scene {
    WindowGroup {
      Text("Tanzaku")
        .font(.largeTitle)
    }
  }
}
