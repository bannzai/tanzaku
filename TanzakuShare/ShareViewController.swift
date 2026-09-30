import SwiftData
import SwiftUI
import TanzakuKit
import UIKit
import UniformTypeIdentifiers

/// 共有シートの拡張の入口 (`Info.plist` の `NSExtensionPrincipalClass`)。共有された文字列 (テキスト・URL) を本文にした新規スニペットの編集画面を出す (`documents/PROJECT.md`「iOS > 共有シート」)。
///
/// 共有シートの拡張の入口は `UIViewController` の派生クラスで作る決まりのため、クラスにする。
final class ShareViewController: UIViewController {
  /// 共有された文字列を読み、編集画面を子の画面として出す。
  override func viewDidLoad() {
    super.viewDidLoad()
    Task {
      let sharedTexts = await loadSharedTexts(extensionItems: extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? [])
      let hostingController = UIHostingController(
        rootView: ShareSnippetView(initialBody: sharedTexts.joined(separator: "\n")) { [weak self] in
          self?.extensionContext?.completeRequest(returningItems: nil)
        }
      )
      addChild(hostingController)
      hostingController.view.frame = view.bounds
      hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      view.addSubview(hostingController.view)
      hostingController.didMove(toParent: self)
    }
  }
}

/// 共有シートの画面。本体と同じストア (App Group の共有コンテナ) を開き、本体と同じ編集画面を出す。
private struct ShareSnippetView: View {
  /// 共有された文字列。新規スニペットの本文の初期値にする。
  let initialBody: String
  /// 保存・取り消しの後に拡張の要求を終える。
  let onClose: () -> Void

  var body: some View {
    switch iosModelContainerResult {
    case .success(let modelContainer):
      // 埋め込みモデルは読み込まない (`loadEmbeddingModel()` を呼ばない)。共有シートの拡張はメモリの上限が小さく、ベクトルは本体を開いた時に作り直されるため。
      SnippetEditorView(snippet: nil, initialSidebarItem: .library(filter: .all), initialBody: initialBody, onClose: onClose)
        .environment(SnippetEmbeddingController(modelContainer: modelContainer))
        .modelContainer(modelContainer)
    case .failure(let error):
      NavigationStack {
        ContentUnavailableView {
          Label("Could not open snippets", systemImage: "exclamationmark.triangle")
        } description: {
          Text(verbatim: String(describing: error))
        }
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", action: onClose)
          }
        }
      }
    }
  }
}

/// 共有された項目から、テキストと URL の文字列を共有された順に取り出す。テキストでも URL でもない添付は読まない。
///
/// 添付からテキストも URL も読めなかった項目は、項目の本文 (`attributedContentText`) を使う。添付を付けずに本文だけで文字列を渡すアプリがあるため。
/// `NSItemProvider` の読み込みの完了はメインスレッドの外で呼ばれるため、メインスレッドに縛らないよう nonisolated にする。
private nonisolated func loadSharedTexts(extensionItems: [NSExtensionItem]) async -> [String] {
  var sharedTexts: [String] = []
  for extensionItem in extensionItems {
    var extensionItemTexts: [String] = []
    for itemProvider in extensionItem.attachments ?? [] {
      if itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier), let url = await loadSharedObject(itemProvider: itemProvider, objectType: URL.self) {
        extensionItemTexts.append(url.absoluteString)
      } else if itemProvider.hasItemConformingToTypeIdentifier(UTType.text.identifier),
        let text = await loadSharedObject(itemProvider: itemProvider, objectType: String.self)
      {
        extensionItemTexts.append(text)
      }
    }
    if extensionItemTexts.isEmpty, let contentText = extensionItem.attributedContentText?.string, !contentText.isEmpty {
      extensionItemTexts.append(contentText)
    }
    sharedTexts += extensionItemTexts
  }
  return sharedTexts
}

/// `itemProvider` の中身を `objectType` として読む。読めなければ `nil`。
private nonisolated func loadSharedObject<SharedObject: _ObjectiveCBridgeable & Sendable>(
  itemProvider: NSItemProvider,
  objectType: SharedObject.Type
) async -> SharedObject? where SharedObject._ObjectiveCType: NSItemProviderReading {
  await withCheckedContinuation { continuation in
    _ = itemProvider.loadObject(ofClass: objectType) { sharedObject, _ in
      continuation.resume(returning: sharedObject)
    }
  }
}
