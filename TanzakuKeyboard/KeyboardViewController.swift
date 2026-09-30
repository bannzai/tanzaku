import SwiftUI
import UIKit

/// カスタムキーボードの入口 (`Info.plist` の `NSExtensionPrincipalClass`)。SwiftUI のキーボードの画面を出し、入力欄との受け渡しをする (`documents/PROJECT.md`「iOS > カスタムキーボード」)。
///
/// キーボードの拡張の入口は `UIInputViewController` の派生クラスで作る決まりのため、クラスにする。
final class KeyboardViewController: UIInputViewController {
  /// SwiftUI の画面へ渡す、入口が受け取る状態。
  private let keyboardHostState = KeyboardHostState()
  /// キーボードの高さ。SwiftUI の画面の高さは入力欄との間で決まらないため、画面が出す部分に合わせて入口で決める。
  private var keyboardHeightConstraint: NSLayoutConstraint?

  /// キーボードの画面を子の画面として出す。
  override func viewDidLoad() {
    super.viewDidLoad()
    let hostingController = UIHostingController(
      rootView: KeyboardView(
        keyboardHostState: keyboardHostState,
        textDocumentProxy: textDocumentProxy,
        advanceToNextInputMode: { [weak self] in
          self?.advanceToNextInputMode()
        },
        setKeyboardHeight: { [weak self] keyboardHeight in
          self?.keyboardHeightConstraint?.constant = keyboardHeight
        }
      )
    )
    // キーボードの背景はシステムのもの (入力欄のアプリの外観に合わせた色) を見せる。
    hostingController.view.backgroundColor = .clear
    // キーボードの下の端の余白はシステムが取るため、SwiftUI の画面では安全領域を空けない。
    hostingController.safeAreaRegions = []
    addChild(hostingController)
    hostingController.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(hostingController.view)
    // 高さの制約は、キーボードを出す途中のシステムの一時的な高さの制約とぶつかっても壊れないよう、必須より 1 つ低くする。
    let keyboardHeightConstraint = view.heightAnchor.constraint(equalToConstant: keyboardTypingHeight)
    keyboardHeightConstraint.priority = UILayoutPriority(999)
    NSLayoutConstraint.activate([
      hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
      hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      keyboardHeightConstraint,
    ])
    self.keyboardHeightConstraint = keyboardHeightConstraint
    hostingController.didMove(toParent: self)
  }

  /// 次のキーボードへの切り替えのキーを出すかとフルアクセスの有無を読む。どちらもキーボードの画面を並べる時にしか決まらないため、ここで読む。
  ///
  /// 並べ直すたびに呼ばれるため、変わった時だけ書き込み、SwiftUI の画面を無駄に描き直させない。
  override func viewWillLayoutSubviews() {
    super.viewWillLayoutSubviews()
    if keyboardHostState.needsInputModeSwitchKey != needsInputModeSwitchKey {
      keyboardHostState.needsInputModeSwitchKey = needsInputModeSwitchKey
    }
    if keyboardHostState.hasFullAccess != hasFullAccess {
      keyboardHostState.hasFullAccess = hasFullAccess
    }
  }

  /// 入力欄の文字やカーソルが変わったことを画面へ知らせる。画面はスニペットグループのキーワードを判定し直す。
  override func textDidChange(_ textInput: (any UITextInput)?) {
    super.textDidChange(textInput)
    keyboardHostState.textChangeCount += 1
  }
}

/// キーボードの画面が入口 (`KeyboardViewController`) から受け取る状態。`UIInputViewController` が持つ値と通知を SwiftUI の画面の描き直しにつなぐため、観測できるクラスにする。
@Observable
final class KeyboardHostState {
  /// 次のキーボードへの切り替えのキーを出すか (`UIInputViewController.needsInputModeSwitchKey`)。ホームボタンの無い端末ではシステムが切り替えのキーを出すため `false` になる。
  var needsInputModeSwitchKey = false
  /// ユーザーがフルアクセスを許可したか (`UIInputViewController.hasFullAccess`)。
  var hasFullAccess = false
  /// 入力欄の文字やカーソルが変わった回数 (`textDidChange(_:)`)。変わったことだけを画面へ知らせるため、入力欄の文字は持たない。
  var textChangeCount = 0
}
