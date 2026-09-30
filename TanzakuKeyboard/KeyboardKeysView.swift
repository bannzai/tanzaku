import SwiftUI

/// 文字のキーの面。iOS の標準の英語のキーボードと同じく、英字・数字・記号の 3 つを切り替える。
enum KeyboardKeyPage {
  /// 英字。
  case letters
  /// 数字とよく使う記号。
  case numbers
  /// 残りの記号。
  case symbols
}

/// 文字のキーの面の上 2 段の文字。並びは iOS の標準の英語のキーボードと同じにし、切り替えた人が迷わないようにする。
private func keyboardUpperCharacterRows(keyPage: KeyboardKeyPage) -> [[String]] {
  switch keyPage {
  case .letters:
    [["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"], ["a", "s", "d", "f", "g", "h", "j", "k", "l"]]
  case .numbers:
    [["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"], ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""]]
  case .symbols:
    [["[", "]", "{", "}", "#", "%", "^", "*", "+", "="], ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"]]
  }
}

/// 文字のキーの面の 3 段目の文字。左の端は英字ではシフト、数字と記号では面の切り替え、右の端は削除のキーを置く。
private func keyboardLowerCharacterRow(keyPage: KeyboardKeyPage) -> [String] {
  switch keyPage {
  case .letters:
    ["z", "x", "c", "v", "b", "n", "m"]
  case .numbers, .symbols:
    [".", ",", "?", "!", "'"]
  }
}

/// キーとキーの間の幅。iOS の標準のキーボードの見た目に合わせた値。
private let keyboardKeySpacing: CGFloat = 6
/// 段と段の間の高さ。iOS の標準のキーボードの見た目に合わせた値。
private let keyboardRowSpacing: CGFloat = 11
/// シフト・削除・面の切り替えのキーの幅の、文字のキーの幅に対する倍率。iOS の標準のキーボードで 3 段目の両端のキーが文字のキーの約 1.3 倍のため。
private let keyboardFunctionKeyWidthRatio: CGFloat = 1.3
/// 改行のキーの幅の、文字のキーの幅に対する倍率。iOS の標準のキーボードの改行のキーが文字のキーの約 2.3 倍のため。
private let keyboardReturnKeyWidthRatio: CGFloat = 2.3

/// 文字のキーの 4 段。文字の入力・削除・改行・空白・面の切り替え・次のキーボードへの切り替えを持つ。フルアクセスが無くても使える (Guideline 4.4.1)。
struct KeyboardKeysView: View {
  /// 出す面。
  var keyPage: KeyboardKeyPage
  /// 英字を大文字で出して打つか。
  var isShifted: Bool
  /// 次のキーボードへの切り替えのキーを出すか。
  var showsInputModeSwitchKey: Bool
  /// 文字・空白を打った。
  var onInsert: (String) -> Void
  /// 削除のキーを押した。
  var onDelete: () -> Void
  /// シフトのキーを押した。
  var onShift: () -> Void
  /// 面の切り替えのキーを押した。
  var onKeyPageChange: (KeyboardKeyPage) -> Void
  /// 改行のキーを押した。
  var onReturn: () -> Void
  /// 次のキーボードへの切り替えのキーを押した。
  var onAdvanceToNextInputMode: () -> Void

  var body: some View {
    GeometryReader { geometry in
      // 1 段目に並ぶ 10 個の文字のキーで横幅を埋める幅を、文字のキーの幅にする。幅が決まる前 (0) に負の幅にしない。
      let characterKeyWidth = max(0, (geometry.size.width - keyboardKeySpacing * 11) / 10)
      let upperCharacterRows = keyboardUpperCharacterRows(keyPage: keyPage)
      VStack(spacing: keyboardRowSpacing) {
        ForEach(upperCharacterRows, id: \.self) { characterRow in
          HStack(spacing: keyboardKeySpacing) {
            ForEach(characterRow, id: \.self) { character in
              characterKey(character: character)
                .frame(width: characterKeyWidth)
            }
          }
        }
        HStack(spacing: keyboardKeySpacing) {
          lowerRowLeadingKey
            .frame(width: characterKeyWidth * keyboardFunctionKeyWidthRatio)
          Spacer(minLength: 0)
          ForEach(keyboardLowerCharacterRow(keyPage: keyPage), id: \.self) { character in
            characterKey(character: character)
              .frame(width: keyPage == .letters ? characterKeyWidth : characterKeyWidth * keyboardFunctionKeyWidthRatio)
          }
          Spacer(minLength: 0)
          functionKey(action: onDelete) {
            Image(systemName: "delete.left")
          }
          .accessibilityLabel(Text("Delete"))
          .frame(width: characterKeyWidth * keyboardFunctionKeyWidthRatio)
        }
        HStack(spacing: keyboardKeySpacing) {
          functionKey {
            onKeyPageChange(keyPage == .letters ? .numbers : .letters)
          } label: {
            Text(verbatim: keyPage == .letters ? "123" : "ABC")
          }
          .frame(width: characterKeyWidth * keyboardFunctionKeyWidthRatio)
          if showsInputModeSwitchKey {
            functionKey(action: onAdvanceToNextInputMode) {
              Image(systemName: "globe")
            }
            .accessibilityLabel(Text("Next Keyboard"))
            .frame(width: characterKeyWidth * keyboardFunctionKeyWidthRatio)
          }
          keyButton(isFunctionKey: false) {
            onInsert(" ")
          } label: {
            Text("space")
          }
          functionKey(action: onReturn) {
            Text("return")
          }
          .frame(width: characterKeyWidth * keyboardReturnKeyWidthRatio)
        }
      }
      .padding(.horizontal, keyboardKeySpacing)
      .padding(.vertical, 8)
    }
  }

  /// 3 段目の左の端のキー。英字ではシフト、数字では記号の面へ、記号では数字の面へ切り替える。
  @ViewBuilder
  private var lowerRowLeadingKey: some View {
    switch keyPage {
    case .letters:
      functionKey(action: onShift) {
        Image(systemName: isShifted ? "shift.fill" : "shift")
      }
      .accessibilityLabel(Text("Shift"))
    case .numbers:
      functionKey {
        onKeyPageChange(.symbols)
      } label: {
        Text(verbatim: "#+=")
      }
    case .symbols:
      functionKey {
        onKeyPageChange(.numbers)
      } label: {
        Text(verbatim: "123")
      }
    }
  }

  /// 文字のキー。シフトしている時は英字を大文字で出して打つ。
  private func characterKey(character: String) -> some View {
    let displayedCharacter = isShifted && keyPage == .letters ? character.uppercased() : character
    return keyButton(isFunctionKey: false) {
      onInsert(displayedCharacter)
    } label: {
      Text(verbatim: displayedCharacter)
        .font(.title2)
    }
  }

  /// 文字以外のキー (シフト・削除・面の切り替え・次のキーボード・改行)。
  private func functionKey<KeyLabel: View>(action: @escaping () -> Void, @ViewBuilder label: () -> KeyLabel) -> some View {
    keyButton(isFunctionKey: true, action: action, label: label)
  }

  /// 1 つのキー。文字のキーとそれ以外で色を分ける (iOS の標準のキーボードと同じ)。
  private func keyButton<KeyLabel: View>(isFunctionKey: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> KeyLabel) -> some View {
    Button(action: action) {
      label()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
    .buttonStyle(KeyboardKeyButtonStyle(isFunctionKey: isFunctionKey))
  }
}

/// キーの見た目。押している間は色を変え、押したことを分からせる。
private struct KeyboardKeyButtonStyle: ButtonStyle {
  /// 文字以外のキーか。
  var isFunctionKey: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(Color.primary)
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(keyboardKeyColor(isFunctionKey: isFunctionKey != configuration.isPressed))
          .shadow(color: .black.opacity(0.3), radius: 0, x: 0, y: 1)
      )
  }
}

/// キーの背景の色。値は iOS の標準のキーボードのライト・ダークのキーの色に近づけたもの。文字のキーを明るく、それ以外を暗くして見分けやすくする。
private func keyboardKeyColor(isFunctionKey: Bool) -> Color {
  isFunctionKey
    ? appearanceAdaptiveColor(lightHex: 0xABB0BA, darkHex: 0x464646)
    : appearanceAdaptiveColor(lightHex: 0xFFFFFF, darkHex: 0x6B6B6B)
}
