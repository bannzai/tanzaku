#if DEBUG
  import SwiftData
  import SwiftUI
  import TanzakuKit

  /// Debug ビルドだけに出す開発者メニュー。MCP のクライアントを実際に接続しなくても、設定の「AI エージェント」と削除の確認の画面を確かめられるようにする。
  ///
  /// 見本の値は偽のもの (`dummy-token-for-test` など) にする (`.claude/rules/snippet-content-handling.md`)。
  struct DeveloperCommands: Commands {
    /// 見本を入れるストアと、確認の画面を出す先。
    let controller: MCPServerController

    var body: some Commands {
      CommandMenu("Developer") {
        Button("Add Sample MCP Clients") {
          addSampleMCPClients(modelContext: controller.modelContainer.mainContext)
        }
        Button("Show Sample Deletion Request") {
          Task {
            await showSampleDeletionRequest(controller: controller)
          }
        }
      }
    }
  }

  /// 接続済みのクライアントの見本を入れる。名前と最後のアクセスはデザイン (`documents/design/Settings.dc.html`) の見本に合わせる。
  func addSampleMCPClients(modelContext: ModelContext) {
    let now = Date.now
    for (name, lastUsedAt) in [
      ("Claude Code", now.addingTimeInterval(-2 * 60)),
      ("Claude Desktop", now.addingTimeInterval(-24 * 60 * 60)),
      ("Codex CLI", now.addingTimeInterval(-7 * 24 * 60 * 60)),
    ] {
      let client = MCPClient(id: UUID(), name: name, createdAt: lastUsedAt)
      client.lastUsedAt = lastUsedAt
      modelContext.insert(client)
    }
    try? modelContext.save()
  }

  /// 見本のスニペットを作り、その削除の依頼を確認の画面に出す。内容はデザイン (`documents/design/AgentDelete.dc.html`) の見本に合わせる。許可されたら見本を消す。
  func showSampleDeletionRequest(controller: MCPServerController) async {
    let modelContext = controller.modelContainer.mainContext
    let snippet = Snippet(body: "export API_TOKEN=dummy-token-for-test\nexport DATABASE_URL=postgres://localhost:5432/app_dev\nexport LOG_LEVEL=debug\n\ndotenv_if_exists .env.local")
    snippet.title = String(localized: ".envrc template")
    snippet.keyword = "envrc"
    snippet.colorRawValue = SnippetColor.matsuba.rawValue
    let folder = Folder(name: String(localized: "Dev environment"))
    modelContext.insert(snippet)
    modelContext.insert(folder)
    snippet.folder = folder
    for tagName in ["shell", "direnv"] {
      let tag = Tag(name: tagName)
      modelContext.insert(tag)
      snippet.tags?.append(tag)
    }
    try? modelContext.save()
    let isApproved = await controller.confirmSnippetDeletion(
      request: SnippetDeletionRequest(
        // 見本の依頼はどの接続済みのクライアントにも属さないため、取り消しで拒否されない新しい識別子にする。
        clientID: UUID(),
        clientName: "Claude Code",
        reason: String(localized: "direnv is no longer used, so this template is not needed anymore."),
        snippet: snippet,
        receivedAt: .now
      )
    )
    if isApproved {
      modelContext.delete(snippet)
      try? modelContext.save()
    }
  }
#endif
