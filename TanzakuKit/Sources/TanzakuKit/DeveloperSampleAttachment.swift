#if DEBUG
  import CoreGraphics
  import Foundation
  import ImageIO
  import SwiftData
  import UniformTypeIdentifiers

  /// Mac と iOS の開発者メニューの、見本の画像のスニペットを入れる。ランチャー・一覧・編集画面・クリップボードの画像の表示を、ファイルや写真を選ぶ画面を通さずに確かめるため。保存は呼び出し側で行う。
  ///
  /// キーワード (`developerSampleAttachmentKeyword`) が別のスニペット・スニペットグループで使われていれば入れないため、何度呼んでも増えない。見本の画像を描けなかった時も何も入れない。
  public func insertDeveloperSampleAttachmentSnippet(modelContext: ModelContext, now: Date) throws {
    guard let attachmentData = developerSampleAttachmentPNGData() else {
      return
    }
    do {
      try applySnippetEdit(
        snippet: Snippet(body: ""),
        body: "",
        attachmentData: attachmentData,
        attachmentContentType: UTType.png.identifier,
        attachmentFileName: developerSampleAttachmentFileName,
        title: developerSampleAttachmentTitle,
        keyword: developerSampleAttachmentKeyword,
        language: nil,
        color: .ai,
        folder: nil,
        tagNames: [],
        modelContext: modelContext,
        now: now
      )
    } catch SnippetValidationError.keywordAlreadyUsed {
      return
    }
  }

  /// Mac と iOS の開発者メニューが入れる見本の画像のスニペットのキーワード。
  public let developerSampleAttachmentKeyword = "screenshot"
  /// 見本の画像のスニペットのタイトル。
  public let developerSampleAttachmentTitle = "画面の見本"
  /// 見本の画像のファイル名。見本の削除は、本文 (空) ではなくキーワードとこのファイル名の両方が一致するスニペットを見本とみなす。本文が空のユーザーの添付のスニペットを消さないため。
  public let developerSampleAttachmentFileName = "tanzaku-sample.png"

  /// 見本の画像の PNG のデータ。画面の確認で撮影して公開するため、実在の画面ではなく図形だけを描く。描けなかった時は `nil`。
  ///
  /// 480 × 270 は 16:9 で、一覧・編集画面のプレビューの縮小と、貼り付け先での表示を見分けられる大きさ。色は藍の短冊 (アイコン) と朱・松葉・山吹の帯 (`documents/DIRECTION.md`「デザインの方向」)。
  /// 同じデータを返すため、何度呼んでも見本の添付は変わらない。
  public func developerSampleAttachmentPNGData() -> Data? {
    let width = 480
    let height = 270
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      return nil
    }
    context.setFillColor(CGColor(srgbRed: 0.965, green: 0.969, blue: 0.976, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(srgbRed: 0.153, green: 0.267, blue: 0.494, alpha: 1))
    context.fill(CGRect(x: 200, y: 40, width: 80, height: 190))
    for (index, color) in [
      CGColor(srgbRed: 0.851, green: 0.333, blue: 0.231, alpha: 1),
      CGColor(srgbRed: 0.259, green: 0.506, blue: 0.341, alpha: 1),
      CGColor(srgbRed: 0.886, green: 0.663, blue: 0.180, alpha: 1),
    ].enumerated() {
      context.setFillColor(color)
      context.fill(CGRect(x: 40, y: 60 + index * 60, width: 120, height: 30))
      context.fill(CGRect(x: 320, y: 60 + index * 60, width: 120, height: 30))
    }
    guard let image = context.makeImage() else {
      return nil
    }
    let pngData = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(pngData, UTType.png.identifier as CFString, 1, nil) else {
      return nil
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      return nil
    }
    return pngData as Data
  }
#endif
