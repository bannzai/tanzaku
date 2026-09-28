#if DEBUG
  import AppKit
  import SwiftData
  import SwiftUI
  import TanzakuKit

  /// Debug ビルドだけに出す開発者メニュー。simtunnel の画面の確認で、スニペットがある状態・無い状態とライト・ダークを作るため (`AGENTS.md`「画面の確認」)。
  ///
  /// 開発者向けの操作で翻訳しないため、文言は `Text(verbatim:)` にする。
  struct DeveloperCommands: Commands {
    /// ランチャーとストアを持つアプリの delegate。
    let appDelegate: AppDelegate

    var body: some Commands {
      CommandMenu(Text(verbatim: "Developer")) {
        Button {
          appDelegate.launcherPanelController?.show()
        } label: {
          Text(verbatim: "Open Launcher")
        }
        Divider()
        Button {
          appDelegate.launcherPanelController?.insertSampleSnippets()
        } label: {
          Text(verbatim: "Insert Sample Snippets")
        }
        Button {
          appDelegate.launcherPanelController?.deleteAllSnippets()
        } label: {
          Text(verbatim: "Delete All Snippets")
        }
        Divider()
        Button {
          NSApp.appearance = NSAppearance(named: .aqua)
        } label: {
          Text(verbatim: "Appearance: Light")
        }
        Button {
          NSApp.appearance = NSAppearance(named: .darkAqua)
        } label: {
          Text(verbatim: "Appearance: Dark")
        }
        Button {
          NSApp.appearance = nil
        } label: {
          Text(verbatim: "Appearance: System")
        }
      }
    }
  }

  extension LauncherPanelController {
    /// デザイン (`documents/design/Main.dc.html`) の例と同じスニペットを入れる。同じキーワードのスニペットがあれば入れないため、何度押しても増えない。
    ///
    /// 本文は画面の確認で撮影して公開するため、偽の値だけにする (`.claude/rules/snippet-content-handling.md`)。
    func insertSampleSnippets() {
      let modelContext = modelContainer.mainContext
      do {
        let existingKeywords = Set(try modelContext.fetch(FetchDescriptor<Snippet>()).compactMap(\.keyword))
        let folder = Folder(name: "開発環境")
        let tags = [Tag(name: "shell"), Tag(name: "auth")]
        // 同じ種類の一致は更新日時の新しい順に並ぶため、デザインの並び (envkey が先) になるよう更新日時をずらす。
        let sampleSnippets: [(keyword: String, title: String, body: String, color: SnippetColor, updatedAt: Date)] = [
          (
            "envkey", "環境変数からトークンを取得",
            "# API_TOKEN が未設定ならダミー値で進める\nexport API_TOKEN=\"${API_TOKEN:-dummy-token}\"\n\ncurl -sS \\\n  -H \"Authorization: Bearer ${API_TOKEN}\" \\\n  https://api.example.com/v1/me",
            .shu, Date(timeIntervalSinceNow: 0)
          ),
          ("envrc", ".envrc の雛形", "export API_TOKEN=dummy-token", .matsuba, Date(timeIntervalSinceNow: -60)),
          ("ghsec", "GitHub Actions の secrets 参照", "- run: ./scripts/deploy.sh\n  with:\n    token: ${{ secrets.DEPLOY_TOKEN }}", .ai, Date(timeIntervalSinceNow: -120)),
        ]
        for sampleSnippet in sampleSnippets where !existingKeywords.contains(sampleSnippet.keyword) {
          let snippet = Snippet(body: sampleSnippet.body)
          snippet.title = sampleSnippet.title
          snippet.keyword = sampleSnippet.keyword
          snippet.colorRawValue = sampleSnippet.color.rawValue
          snippet.updatedAt = sampleSnippet.updatedAt
          modelContext.insert(snippet)
          if sampleSnippet.keyword == "envkey" {
            snippet.folder = folder
            snippet.tags = tags
          }
        }
        try modelContext.save()
      } catch {
        assertionFailure("Failed to insert sample snippets: \(error)")
      }
    }

    /// スニペット・フォルダ・タグをすべて消す。結果なしの画面を出すため (意味検索のベクトルがあると、関係の無い入力でも意味が近い欄が埋まる。`documents/DIRECTION.md`「決めたこと」)。
    func deleteAllSnippets() {
      let modelContext = modelContainer.mainContext
      do {
        try modelContext.delete(model: Snippet.self)
        try modelContext.delete(model: Folder.self)
        try modelContext.delete(model: Tag.self)
        try modelContext.delete(model: SnippetEmbedding.self)
        try modelContext.save()
      } catch {
        assertionFailure("Failed to delete snippets: \(error)")
      }
    }
  }
#endif
