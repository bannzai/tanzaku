import AppKit
import Network
import SwiftData
import SwiftUI
import TanzakuKit

/// 確認を待っている削除の依頼。ユーザーの選択を MCP のリクエストの処理へ返す。
struct PendingSnippetDeletion {
  /// 確認に出す依頼。
  var request: SnippetDeletionRequest
  /// 許可 (`true`) か拒否 (`false`) を返す先。必ず 1 回だけ返す。
  var continuation: CheckedContinuation<Bool, Never>
}

/// 待ち受けるポート。デザイン (`documents/design/Settings.dc.html`) の値。
/// 起動のたびに変わると Claude Code に登録した URL が使えなくなるため固定する。
let mcpServerPort = 47831

/// `UserDefaults` の、MCP のサーバーを動かすかのキー。
private let mcpServerEnabledDefaultsKey = "mcpServerEnabled"
/// `UserDefaults` の、MCP からの削除に確認を求めるかのキー。
private let requiresAgentDeletionConfirmationDefaultsKey = "requiresAgentDeletionConfirmation"

/// アプリに内蔵した MCP のサーバーの状態と、設定・削除の確認の画面が使う操作。
///
/// 設定の画面とサーバーの処理が同じ状態 (待ち受けの状態・表示するトークン・確認を待つ依頼) を見るため、SwiftUI が変更を追える `@Observable` のクラスにする。
@Observable
final class MCPServerController {
  /// 待ち受けの状態。
  private(set) var state: MCPServerState = .stopped
  /// 設定に表示する、次に接続するクライアントのためのトークン。Keychain を読めなければ `nil`。
  private(set) var unboundToken: String?
  /// Keychain の操作の失敗。設定に表示する。
  private(set) var tokenErrorMessage: String?
  /// 確認を待っている削除の依頼。先頭を確認の画面に出す。
  private(set) var pendingDeletions: [PendingSnippetDeletion] = []
  /// 意味検索の埋め込みモデル。資産のダウンロードが済むまでは `nil`。
  private(set) var embedder: SnippetTextEmbedder?

  /// MCP のサーバーを動かすか。
  var isServerEnabled: Bool {
    didSet {
      UserDefaults.standard.set(isServerEnabled, forKey: mcpServerEnabledDefaultsKey)
      if isServerEnabled {
        startServer()
      } else {
        stopServer()
      }
    }
  }

  /// MCP からの削除に確認 (Touch ID) を求めるか。
  var requiresDeletionConfirmation: Bool {
    didSet {
      UserDefaults.standard.set(requiresDeletionConfirmation, forKey: requiresAgentDeletionConfirmationDefaultsKey)
    }
  }

  /// スニペットと `MCPClient` のストア。
  @ObservationIgnored let modelContainer: ModelContainer
  /// アクセストークンの保管場所。
  @ObservationIgnored let tokenStore: MCPTokenStore
  /// 待ち受けている listener。止めている時は `nil`。
  @ObservationIgnored private var listener: NWListener?
  /// 削除の確認の画面。確認を待つ依頼が無い時は閉じる。
  @ObservationIgnored private var deletionConfirmationPanel: NSPanel?

  /// 保存した設定を読み、設定で動かしていればサーバーを起動する。
  init(modelContainer: ModelContainer, tokenStore: MCPTokenStore) {
    self.modelContainer = modelContainer
    self.tokenStore = tokenStore
    // 初回起動の最後の手順で AI エージェントを接続するため (`documents/PROJECT.md`「設定・初回起動」)、設定を開かなくても接続できるよう既定は動かす。
    isServerEnabled = UserDefaults.standard.object(forKey: mcpServerEnabledDefaultsKey) as? Bool ?? true
    // 既定はオン (`documents/PROJECT.md`「MCP サーバー」)。
    requiresDeletionConfirmation = UserDefaults.standard.object(forKey: requiresAgentDeletionConfirmationDefaultsKey) as? Bool ?? true
    reloadUnboundToken()
    if isServerEnabled {
      startServer()
    }
  }

  /// 設定と MCP のリクエストの処理が使う環境。
  var serverEnvironment: MCPServerEnvironment {
    MCPServerEnvironment(
      modelContext: modelContainer.mainContext,
      tokenStore: tokenStore,
      port: mcpServerPort,
      embedder: { [weak self] in self?.embedder },
      requiresDeletionConfirmation: { [weak self] in self?.requiresDeletionConfirmation ?? true },
      confirmSnippetDeletion: { [weak self] request in await self?.confirmSnippetDeletion(request: request) ?? false },
      now: { Date.now }
    )
  }

  /// サーバーを起動する。起動済みなら何もしない。
  func startServer() {
    guard listener == nil else {
      return
    }
    do {
      listener = try startMCPHTTPListener(
        port: mcpServerPort,
        handler: { [weak self] request in
          guard let self else {
            return MCPHTTPResponse(statusCode: 503, headers: [:], body: Data())
          }
          let response = await handleMCPHTTPRequest(request: request, environment: serverEnvironment)
          // 設定に表示しているトークンでクライアントが接続すると、そのトークンはクライアントのものになるため、次のクライアントのトークンを表示し直す。
          reloadUnboundToken()
          return response
        },
        stateDidChange: { [weak self] state in
          self?.state = state
          if case .failed = state {
            self?.listener = nil
          }
        }
      )
    } catch {
      state = .failed(message: error.localizedDescription)
    }
  }

  /// サーバーを止める。止めていれば何もしない。
  func stopServer() {
    listener?.cancel()
    listener = nil
    state = .stopped
  }

  /// 意味検索の埋め込みモデルの資産を用意し、使えるようになったら MCP の検索と保存で使う。
  func prepareEmbedder() async {
    let language = snippetEmbeddingLanguage(preferredLanguages: Locale.preferredLanguages)
    guard (try? await requestContextualEmbeddingAssets(language: language)) == true else {
      return
    }
    embedder = try? makeContextualSnippetTextEmbedder(language: language)
  }

  /// 表示するトークンを Keychain から読み直す。無ければ作る。
  func reloadUnboundToken() {
    do {
      unboundToken = try mcpUnboundToken(tokenStore: tokenStore)
      tokenErrorMessage = nil
    } catch {
      unboundToken = nil
      tokenErrorMessage = "\(error)"
    }
  }

  /// 表示しているトークンを作り直す。
  func reissueUnboundToken() {
    do {
      unboundToken = try reissueMCPUnboundToken(tokenStore: tokenStore)
      tokenErrorMessage = nil
    } catch {
      tokenErrorMessage = "\(error)"
    }
  }

  /// クライアントの接続を取り消す。
  func revoke(client: MCPClient) {
    do {
      try revokeMCPClient(client: client, modelContext: modelContainer.mainContext, tokenStore: tokenStore)
      tokenErrorMessage = nil
    } catch {
      tokenErrorMessage = "\(error)"
    }
  }

  /// 削除の確認を出し、ユーザーが選ぶまで待つ。確認を待つ依頼が複数あれば、届いた順に 1 件ずつ出す。
  func confirmSnippetDeletion(request: SnippetDeletionRequest) async -> Bool {
    await withCheckedContinuation { continuation in
      pendingDeletions.append(PendingSnippetDeletion(request: request, continuation: continuation))
      showDeletionConfirmationPanel()
    }
  }

  /// 削除の依頼へのユーザーの選択を返す。同じ依頼に 2 回返さないよう、確認を待つ依頼から外してから返す。
  func resolveDeletion(requestID: UUID, isApproved: Bool) {
    guard let index = pendingDeletions.firstIndex(where: { $0.request.id == requestID }) else {
      return
    }
    pendingDeletions.remove(at: index).continuation.resume(returning: isApproved)
    if pendingDeletions.isEmpty {
      deletionConfirmationPanel?.close()
      deletionConfirmationPanel = nil
    }
  }

  /// 削除の確認の画面を前面に出す。
  ///
  /// MCP の依頼はほかのアプリを使っている間に届くため、アプリを前面に出してから見せる。画面はキャンセルか削除でだけ閉じられるよう、閉じるボタンを持たない。
  private func showDeletionConfirmationPanel() {
    let panel =
      deletionConfirmationPanel
      ?? {
        let panel = NSPanel(
          contentRect: .zero,
          styleMask: [.titled, .fullSizeContentView],
          backing: .buffered,
          defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.contentViewController = NSHostingController(rootView: AgentDeleteConfirmationPanelContent(controller: self))
        deletionConfirmationPanel = panel
        return panel
      }()
    NSApp.activate()
    panel.center()
    panel.makeKeyAndOrderFront(nil)
  }
}
