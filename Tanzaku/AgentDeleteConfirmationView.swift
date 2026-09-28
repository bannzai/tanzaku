import SwiftUI
import TanzakuKit

/// 削除の確認の画面の中身。確認を待つ依頼の先頭を出す。
struct AgentDeleteConfirmationPanelContent: View {
  /// 確認を待つ依頼と、選択を返す先。
  let controller: MCPServerController

  var body: some View {
    if let pendingDeletion = controller.pendingDeletions.first {
      AgentDeleteConfirmationView(request: pendingDeletion.request) { isApproved in
        controller.resolveDeletion(requestID: pendingDeletion.request.id, isApproved: isApproved)
      }
      // 依頼ごとに認証中の状態を作り直すため。
      .id(pendingDeletion.request.id)
    }
  }
}

/// AI エージェントからの削除の依頼を確認する画面 (`documents/design/AgentDelete.dc.html`)。
///
/// 依頼元のクライアント名・エージェントが書いた理由・削除するスニペットの全文を見せ、Touch ID (無い Mac ではパスワード) で認証できた時だけ削除を許可する。
struct AgentDeleteConfirmationView: View {
  /// 確認する依頼。
  let request: SnippetDeletionRequest
  /// ユーザーの選択 (許可なら `true`) を返す。
  let resolve: (Bool) -> Void

  /// 認証の画面を出している間は、ボタンを押せなくする。
  @State private var isAuthenticating = false

  /// スクロールなしで本文を並べる最大の行数。これより長い本文はスクロールで全文を見せ、確認の画面が画面の外まで伸びないようにする。
  ///
  /// 12 行はデザインの見本 (5 行の `.envrc`) の 2 倍を超える。12 行の本文 (1 行 約 20pt) を入れても確認の画面が約 600pt に収まり、13 インチの MacBook の画面 (高さ 800pt 前後) でもはみ出さないため。
  private let bodyLineCountWithoutScroll = 12

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top, spacing: 14) {
        AgentDeleteAppIcon()
        VStack(alignment: .leading, spacing: 6) {
          Text("\(request.clientName) wants to delete a snippet")
            .font(.system(size: 15, weight: .bold))
          Text("This request came through MCP. Check what will be deleted and confirm with Touch ID.")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
      }

      Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
        GridRow {
          Text("Requested by")
            .foregroundStyle(.tertiary)
          HStack(spacing: 6) {
            Circle()
              .fill(SnippetColor.matsuba.color)
              .frame(width: 7, height: 7)
            Text("\(request.clientName) (connected client)")
          }
        }
        GridRow {
          Text("Action")
            .foregroundStyle(.tertiary)
          Text("Delete 1 snippet")
        }
        GridRow {
          Text("Agent's reason")
            .foregroundStyle(.tertiary)
          Text("“\(request.reason)”")
            .fixedSize(horizontal: false, vertical: true)
        }
        GridRow {
          Text("Received")
            .foregroundStyle(.tertiary)
          Text(request.receivedAt, format: .dateTime.hour().minute())
        }
      }
      .font(.system(size: 12))
      .padding(.vertical, 12)
      .padding(.horizontal, 14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

      VStack(alignment: .leading, spacing: 8) {
        Text("Snippet to delete")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.secondary)
        HStack(alignment: .top, spacing: 12) {
          if let color = request.snippet.colorRawValue.flatMap({ SnippetColor(rawValue: $0) }) {
            RoundedRectangle(cornerRadius: 2)
              .fill(color.color)
              .frame(width: 4)
          }
          VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
              Text(snippetDisplayTitle(snippet: request.snippet))
                .font(.system(size: 14, weight: .semibold))
              Text(snippetMetadataText(snippet: request.snippet))
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            }
            .lineLimit(1)
            snippetBodyView
          }
        }
        .padding(14)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
      }

      HStack(spacing: 10) {
        Text("You can allow deletion without confirmation in Settings › AI Agents")
          .font(.system(size: 12))
          .foregroundStyle(.tertiary)
          .frame(maxWidth: .infinity, alignment: .leading)
        Button("Cancel") {
          resolve(false)
        }
        .keyboardShortcut(.cancelAction)
        .disabled(isAuthenticating)
        Button {
          isAuthenticating = true
          Task {
            resolve(await authenticateSnippetDeletion(clientName: request.clientName))
          }
        } label: {
          Label("Delete with Touch ID", systemImage: "touchid")
            .fontWeight(.semibold)
        }
        .buttonStyle(.borderedProminent)
        .tint(appearanceAdaptiveColor(lightHex: 0xB8321E, darkHex: 0xB8321E))
        .disabled(isAuthenticating)
      }
      .controlSize(.large)
    }
    .padding(EdgeInsets(top: 28, leading: 28, bottom: 24, trailing: 28))
    .frame(width: 540)
  }

  /// 削除するスニペットの全文。本文は言語を問わず等幅で出す (`documents/DIRECTION.md`「決めたこと」)。
  @ViewBuilder
  private var snippetBodyView: some View {
    let bodyText = Text(request.snippet.body)
      .font(.system(size: 12, design: .monospaced))
      .lineSpacing(3)
      .textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 10)
      .padding(.horizontal, 12)
    Group {
      if request.snippet.body.split(separator: "\n", omittingEmptySubsequences: false).count <= bodyLineCountWithoutScroll {
        bodyText
      } else {
        ScrollView {
          bodyText
        }
        .frame(height: 240)
      }
    }
    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
  }
}

/// キーワード・タグ・フォルダを 1 行にした文言。無いものは出さない。
func snippetMetadataText(snippet: Snippet) -> String {
  [
    snippet.keyword.flatMap { $0.isEmpty ? nil : String(localized: "Keyword \($0)") },
    (snippet.tags ?? []).isEmpty ? nil : String(localized: "Tags \((snippet.tags ?? []).map(\.name).sorted().joined(separator: ", "))"),
    snippet.folder.map { String(localized: "Folder \($0.name)") },
  ]
  .compactMap { $0 }
  .joined(separator: " · ")
}

/// 確認の画面の左上に出すアプリのアイコン (藍の短冊 1 枚)。
struct AgentDeleteAppIcon: View {
  var body: some View {
    ZStack(alignment: .top) {
      RoundedRectangle(cornerRadius: 10)
        .fill(.quaternary)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
      RoundedRectangle(cornerRadius: 2)
        .fill(SnippetColor.ai.color)
        .frame(width: 12, height: 28)
        .overlay(alignment: .top) {
          Circle()
            .fill(Color(nsColor: .windowBackgroundColor))
            .frame(width: 3.2, height: 3.2)
            .padding(.top, 3)
        }
        .padding(.top, 8)
    }
    .frame(width: 44, height: 44)
  }
}
