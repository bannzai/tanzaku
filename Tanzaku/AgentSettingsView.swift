import AppKit
import SwiftData
import SwiftUI
import TanzakuKit

/// 設定の「AI エージェント」(`documents/design/Settings.dc.html`)。MCP のサーバーの状態・接続のコマンド・アクセストークン・接続済みのクライアント・削除の確認を扱う。
struct AgentSettingsView: View {
  @Environment(MCPServerController.self) private var controller
  /// 接続を許可したクライアント。許可した順に並べる。
  @Query(sort: \MCPClient.createdAt) private var clients: [MCPClient]
  /// トークンの再発行の確認を出しているか。
  @State private var isReissueConfirmationPresented = false

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
            Button("Revoke", role: .destructive) {
              controller.revoke(client: client)
            }
            .foregroundStyle(.red)
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
    SnippetColor.matsuba.color
  case .starting:
    SnippetColor.yamabuki.color
  case .failed:
    SnippetColor.shu.color
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
