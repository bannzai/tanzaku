import SwiftUI

/// メインウィンドウの中身。雛形の段階の仮の画面で、画面構成はデザインの関門で決める。
struct ContentView: View {
  var body: some View {
    Text("Tanzaku")
      .font(.largeTitle)
      .frame(minWidth: 480, minHeight: 320)
  }
}

#Preview {
  ContentView()
}
