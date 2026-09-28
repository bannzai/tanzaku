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
      // パネルはタイトルバーを隠して内容を上端まで広げているため、タイトルバーの分の余白を空けない。
      .ignoresSafeArea()
      // 本文と理由の高さを測った後に内容の高さが変わるため、そのたびにパネルの大きさを内容に合わせる。
      .onGeometryChange(for: CGSize.self) { geometry in
        geometry.size
      } action: { size in
        controller.resizeDeletionConfirmationPanel(contentSize: size)
      }
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
  /// 折り返した後の本文の高さ。スクロールの枠の高さを決めるために測る。
  @State private var bodyTextHeight: CGFloat = 0
  /// 折り返した後の理由の高さ。スクロールの枠の高さを決めるために測る。
  @State private var reasonTextHeight: CGFloat = 0

  /// スクロールなしで本文を並べる最大の高さ。これより高い本文 (改行が多いものも、折り返しで長くなるものも) はスクロールで全文を見せ、確認の画面が画面の外まで伸びないようにする。
  ///
  /// 240pt は 12 行ほど (1 行 約 20pt) で、デザインの見本 (5 行の `.envrc`) の 2 倍を超える。本文を 240pt にしても確認の画面が約 600pt に収まり、13 インチの MacBook の画面 (高さ 800pt 前後) でもはみ出さないため。
  private let bodyMaximumHeightWithoutScroll: CGFloat = 240

  /// スクロールなしでエージェントの理由を並べる最大の高さ。
  ///
  /// 80pt は 12pt の文字で 5 行ほどで、デザインの見本の理由 (2 行) を折り返しても収まり、本文の上限 (240pt) と合わせても確認の画面が 13 インチの MacBook の画面に収まるため。
  private let reasonMaximumHeightWithoutScroll: CGFloat = 80

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
        // 理由はスクロールの中に置くため文字のベースラインで揃えられず、見出しを理由の最後の行に揃えてしまうため、上端で揃える。
        GridRow(alignment: .top) {
          Text("Agent's reason")
            .foregroundStyle(.tertiary)
          // 理由の長さはエージェント次第のため、長い理由はスクロールで全文を見せ、確認の画面が画面の外まで伸びないようにする。
          ScrollView {
            Text("“\(request.reason)”")
              .frame(maxWidth: .infinity, alignment: .leading)
              .fixedSize(horizontal: false, vertical: true)
              .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.height
              } action: { height in
                reasonTextHeight = height
              }
          }
          .frame(height: min(reasonTextHeight, reasonMaximumHeightWithoutScroll))
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
    // 本文と理由の高さを測った後にパネルの高さを内容に合わせるため、余った高さを内容に配らず、内容の高さそのものを求める。
    .fixedSize(horizontal: false, vertical: true)
  }

  /// 削除するスニペットの全文。本文は言語を問わず等幅で出す (`documents/DIRECTION.md`「決めたこと」)。
  @ViewBuilder
  private var snippetBodyView: some View {
    // ScrollView は内容の高さを自分の高さにしないため、折り返した後の本文の高さを測って枠の高さを決める。
    ScrollView {
      Text(request.snippet.body)
        .font(.system(size: 12, design: .monospaced))
        .lineSpacing(3)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { geometry in
          geometry.size.height
        } action: { height in
          bodyTextHeight = height
        }
    }
    .frame(height: min(bodyTextHeight, bodyMaximumHeightWithoutScroll))
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
