import AppKit
import SwiftData
import SwiftUI
import TanzakuKit

/// 設定の「AI エージェント」(`documents/design/Settings.dc.html`)。MCP のサーバーの状態・接続のコマンド・アクセストークン・接続済みのクライアント・承認待ちのスニペット・削除の確認を扱う。
struct AgentSettingsView: View {
  @Environment(MCPServerController.self) private var controller
  @Environment(\.modelContext) private var modelContext
  /// 接続を許可したクライアント。最近使った順に並べ、まだ使っていないものは許可した新しい順に続ける。
  @Query(sort: [SortDescriptor(\MCPClient.lastUsedAt, order: .reverse), SortDescriptor(\MCPClient.createdAt, order: .reverse)])
  private var clients: [MCPClient]
  /// キーワードを持つスニペット。更新の新しい順。承認待ちかの判定は `snippetIsAwaitingKeywordExpansionApproval(snippet:)` を正とし、`#Predicate` に写さない。
  @Query(filter: #Predicate<Snippet> { $0.keyword != nil }, sort: [SortDescriptor(\Snippet.updatedAt, order: .reverse)])
  private var keywordSnippets: [Snippet]
  /// トークンの再発行の確認を出しているか。
  @State private var isReissueConfirmationPresented = false
  /// 承認の保存に失敗した理由。
  @State private var approvalErrorMessage: String?

  /// キーワード展開の承認を待っているスニペット。キーワードの無いスニペットは展開されないため並べない。
  private var awaitingApprovalSnippets: [Snippet] {
    keywordSnippets.filter { snippetIsAwaitingKeywordExpansionApproval(snippet: $0) }
  }

  var body: some View {
    @Bindable var controller = controller
    Form {
      Section {
        Toggle(isOn: $controller.isServerEnabled) {
          Text("MCP server")
          Text("AI agents can search, add, and organize your snippets. The server listens only inside this Mac (127.0.0.1).")
        }
        LabeledContent("Status") {
          HStack(spacing: 6) {
            Circle()
              .fill(mcpServerStateColor(state: controller.state))
              .frame(width: 8, height: 8)
            Text(mcpServerStateText(state: controller.state))
          }
        }
      }

      Section("Connection") {
        VStack(alignment: .leading, spacing: 8) {
          Text("Command to add to Claude Code")
          HStack(spacing: 10) {
            Text(mcpAddCommand(token: controller.unboundToken.map { maskedMCPAccessToken(token: $0) } ?? "…"))
              .font(.system(size: 12, design: .monospaced))
              .lineLimit(1)
              .truncationMode(.middle)
              .padding(.vertical, 8)
              .padding(.horizontal, 10)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            Button("Copy") {
              copyToPasteboard(text: mcpAddCommand(token: controller.unboundToken ?? ""))
            }
            .disabled(controller.unboundToken == nil)
          }
        }
        LabeledContent {
          HStack {
            Button("Copy") {
              copyToPasteboard(text: controller.unboundToken ?? "")
            }
            .disabled(controller.unboundToken == nil)
            Button("Reissue…") {
              isReissueConfirmationPresented = true
            }
          }
        } label: {
          Text("Access token")
          Text(controller.unboundToken.map { maskedMCPAccessToken(token: $0) } ?? "")
            .font(.system(size: 12, design: .monospaced))
        }
        if let tokenErrorMessage = controller.tokenErrorMessage {
          Text(tokenErrorMessage)
            .foregroundStyle(.red)
        }
      }

      Section("Connected clients") {
        if clients.isEmpty {
          Text("No AI agent has connected yet. Run the command above in your terminal.")
            .foregroundStyle(.secondary)
        }
        ForEach(clients) { client in
          LabeledContent {
            // デザインの「取り消す」は通常のボタンに赤い文字のため、role で背景まで赤くしない。
            Button {
              controller.revoke(client: client)
            } label: {
              Text("Revoke")
                .foregroundStyle(.red)
            }
          } label: {
            Text(client.name)
            if let lastUsedAt = client.lastUsedAt {
              Text("Last access \(lastUsedAt, format: .relative(presentation: .named))")
            } else {
              Text("Not used yet")
            }
          }
        }
      }

      Section {
        if awaitingApprovalSnippets.isEmpty {
          Text("No snippets are awaiting approval.")
            .foregroundStyle(.secondary)
        }
        ForEach(awaitingApprovalSnippets) { snippet in
          AwaitingApprovalSnippetRow(snippet: snippet) {
            approve(snippet: snippet)
          }
        }
        if let approvalErrorMessage {
          Text(approvalErrorMessage)
            .foregroundStyle(.red)
        }
      } header: {
        Text("Awaiting approval")
      } footer: {
        Text("Keywords of snippets that AI agents added or changed do not expand until you approve them. Saving a snippet in the editor also approves it.")
      }

      Section {
        Toggle(isOn: $controller.requiresDeletionConfirmation) {
          Text("Require Touch ID to delete")
          Text("Deletions from AI agents are not performed until you confirm with Touch ID.")
        }
      }
    }
    .formStyle(.grouped)
    .confirmationDialog("Reissue the access token?", isPresented: $isReissueConfirmationPresented) {
      Button("Reissue") {
        controller.reissueUnboundToken()
      }
    } message: {
      Text("The current token stops working. Clients that are already connected keep their own tokens.")
    }
  }

  /// スニペットを承認してキーワード展開に使えるようにする。保存に失敗したら承認を取り消して理由を出す。
  private func approve(snippet: Snippet) {
    do {
      try approveSnippetKeywordExpansion(snippet: snippet, modelContext: modelContext)
      approvalErrorMessage = nil
    } catch {
      modelContext.rollback()
      approvalErrorMessage = String(localized: "Could not approve: \(error.localizedDescription)")
    }
  }
}

/// 承認待ちのスニペットの 1 行。承認する前に展開される文面をすべて見られるよう、本文を省略せずに出す。
private struct AwaitingApprovalSnippetRow: View {
  let snippet: Snippet
  /// 「承認」を押した時の処理。
  let onApprove: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(verbatim: snippet.keyword ?? "")
          .font(.system(size: 12, weight: .semibold, design: .monospaced))
        Text(verbatim: snippetDisplayTitle(snippet: snippet))
          .lineLimit(1)
          .truncationMode(.tail)
        Spacer()
        Button("Approve", action: onApprove)
      }
      Text("Updated \(snippet.updatedAt, format: .dateTime.month().day()) (changed by \(snippet.updatedByClientName ?? "") via MCP)")
        .font(.caption)
        .foregroundStyle(.secondary)
      if let attachmentContentType = snippet.attachmentContentType {
        Label(snippetAttachmentFileName(originalFileName: snippet.attachmentFileName, contentType: attachmentContentType), systemImage: "photo")
          .font(.system(size: 12))
      } else {
        Text(verbatim: snippet.body)
          .font(.system(size: 12, design: .monospaced))
          .textSelection(.enabled)
          .padding(.vertical, 8)
          .padding(.horizontal, 10)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
      }
    }
    .padding(.vertical, 4)
  }
}

/// Claude Code に MCP のサーバーを登録するコマンド ( https://code.claude.com/docs/en/mcp )。
func mcpAddCommand(token: String) -> String {
  "claude mcp add --transport http \(mcpServerName) http://127.0.0.1:\(mcpServerPort)\(mcpEndpointPath) --header \"Authorization: Bearer \(token)\""
}

/// 画面に出すトークン。肩越しに見られても使えないよう、先頭だけを出す。先頭はトークンの見分けに使う。
func maskedMCPAccessToken(token: String) -> String {
  "\(token.prefix(8))••••••••"
}

/// 状態の点の色。
func mcpServerStateColor(state: MCPServerState) -> Color {
  switch state {
  case .running:
    snippetBandColor(snippetColor: .matsuba)
  case .starting:
    snippetBandColor(snippetColor: .yamabuki)
  case .failed:
    snippetBandColor(snippetColor: .shu)
  case .stopped:
    Color.secondary
  }
}

/// 状態の文言。
func mcpServerStateText(state: MCPServerState) -> String {
  switch state {
  case .running(let port):
    String(localized: "Running · Port \(String(port))")
  case .starting:
    String(localized: "Starting")
  case .failed(let message):
    String(localized: "Could not start: \(message)")
  case .stopped:
    String(localized: "Stopped")
  }
}

/// 文字列をクリップボードに入れる。
func copyToPasteboard(text: String) {
  NSPasteboard.general.clearContents()
  NSPasteboard.general.setString(text, forType: .string)
}
