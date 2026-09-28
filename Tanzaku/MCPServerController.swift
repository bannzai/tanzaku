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

/// ほかのスレッドで読み込んだ埋め込みモデルを、メインアクターへ渡すための入れ物。
///
/// `SnippetTextEmbedder` はクロージャを持つため Sendable ではない。検索のクエリ用のモデルは読み込んだ後はメインアクターだけが使い、
/// ベクトルの作り直し用のモデルは一度に 1 つの作り直し (`requestSnippetEmbeddingRefresh()`) だけが使うため、同じモデルを同時に使うことはない。
nonisolated struct UncheckedSendableEmbedder: @unchecked Sendable {
  /// 読み込んだ埋め込みモデル。読み込めなければ `nil`。
  var embedder: SnippetTextEmbedder?
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
  let modelContainer: ModelContainer
  /// アクセストークンの保管場所。
  let tokenStore: MCPTokenStore
  /// 待ち受けている listener。止めている時は `nil`。
  @ObservationIgnored private var listener: NWListener?
  /// 削除の確認の画面。確認を待つ依頼が無い時は閉じる。
  @ObservationIgnored private var deletionConfirmationPanel: NSPanel?
  /// 削除の確認の画面の内容の、最後に測った大きさ。
  @ObservationIgnored private var deletionConfirmationContentSize: CGSize?
  /// ベクトルの作り直しだけに使う埋め込みモデル。資産のダウンロードが済むまでは `nil`。
  @ObservationIgnored private var snippetEmbeddingRefreshEmbedder: UncheckedSendableEmbedder?
  /// ベクトルを作り直している途中か。
  @ObservationIgnored private var isRefreshingSnippetEmbeddings = false
  /// 作り直しを頼まれてから、まだ作り直していないか。
  @ObservationIgnored private var needsSnippetEmbeddingRefresh = false

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

  /// MCP のリクエストの処理が使う環境。
  ///
  /// リクエストごとに新しいコンテキストを使う。失敗したツールの変更を取り消す (`rollback()`) 時に、画面が `mainContext` に持つ保存前の編集まで消さないため。
  var serverEnvironment: MCPServerEnvironment {
    MCPServerEnvironment(
      modelContext: ModelContext(modelContainer),
      tokenStore: tokenStore,
      port: mcpServerPort,
      embedder: { [weak self] in self?.embedder },
      snippetsDidChange: { [weak self] in self?.requestSnippetEmbeddingRefresh() },
      requiresDeletionConfirmation: { [weak self] in self?.requiresDeletionConfirmation ?? true },
      confirmSnippetDeletion: { [weak self] request in await self?.confirmSnippetDeletion(request: request) ?? false },
      cancelClientRequest: { [weak self] clientID, rpcRequestID in
        self?.cancelDeletion(clientID: clientID, rpcRequestID: rpcRequestID)
      },
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
          // 止める前に受け付けた接続から、止めた後にリクエストが届くことがあるため、止めた後は処理しない。
          guard let self, isServerEnabled, listener != nil else {
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

  /// 意味検索の埋め込みモデルの資産を用意し、使えるようになったら MCP の検索とベクトルの作り直しで使う。
  ///
  /// モデルの準備が済む前に保存したスニペットにはベクトルが無いため、準備が済んだらすべてのスニペットのベクトルを作り直す。
  func prepareEmbedder() async {
    let language = snippetEmbeddingLanguage(preferredLanguages: Locale.preferredLanguages)
    guard (try? await requestContextualEmbeddingAssets(language: language)) == true else {
      return
    }
    // 埋め込みモデルの読み込み (NLContextualEmbedding の load()) はモデルの大きさの分だけ時間が掛かり、
    // メインスレッドで行うと、その間は画面も MCP のリクエストの処理も止まるため、ほかのスレッドで行う。
    // 検索のクエリ (メインアクター) とベクトルの作り直し (ほかのスレッド) が同じモデルを同時に使わないよう、別々に読み込む。
    let embedders = await Task.detached(priority: .utility) {
      (
        query: UncheckedSendableEmbedder(embedder: try? makeContextualSnippetTextEmbedder(language: language)),
        refresh: UncheckedSendableEmbedder(embedder: try? makeContextualSnippetTextEmbedder(language: language))
      )
    }.value
    embedder = embedders.query.embedder
    snippetEmbeddingRefreshEmbedder = embedders.refresh
    requestSnippetEmbeddingRefresh()
  }

  /// すべてのスニペットの意味検索のベクトルを、今のスニペットに合わせて作り直すよう頼む。
  ///
  /// ベクトルの作成はスニペットの数と長さの分だけ時間が掛かるため、ほかのスレッドで専用のコンテキストを使って行う。
  /// 作り直している間に頼まれたら、その間の変更を取りこぼさないよう、終わった後にもう一度作り直す。
  /// 埋め込みモデルの準備が済む前に頼まれた分は、準備が済んだ時の作り直し (`prepareEmbedder()`) に含まれる。
  func requestSnippetEmbeddingRefresh() {
    needsSnippetEmbeddingRefresh = true
    guard !isRefreshingSnippetEmbeddings, let snippetEmbeddingRefreshEmbedder, snippetEmbeddingRefreshEmbedder.embedder != nil else {
      return
    }
    isRefreshingSnippetEmbeddings = true
    let modelContainer = modelContainer
    Task {
      while needsSnippetEmbeddingRefresh {
        needsSnippetEmbeddingRefresh = false
        await Task.detached(priority: .utility) {
          guard let embedder = snippetEmbeddingRefreshEmbedder.embedder else {
            return
          }
          let modelContext = ModelContext(modelContainer)
          do {
            try updateSnippetEmbeddings(modelContext: modelContext, embedder: embedder)
            try modelContext.save()
          } catch {
            mcpServerLogger.error("Could not update snippet embeddings: \(error.localizedDescription, privacy: .public)")
          }
        }.value
      }
      isRefreshingSnippetEmbeddings = false
    }
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

  /// クライアントの接続を取り消す。取り消したクライアントの確認待ちの削除の依頼は、確認の画面から外して拒否する。
  func revoke(client: MCPClient) {
    let clientID = client.id
    do {
      try revokeMCPClient(client: client, modelContext: modelContainer.mainContext, tokenStore: tokenStore)
      tokenErrorMessage = nil
    } catch {
      tokenErrorMessage = "\(error)"
    }
    for pendingDeletion in pendingDeletions where pendingDeletion.request.clientID == clientID {
      resolveDeletion(requestID: pendingDeletion.request.id, isApproved: false)
    }
  }

  /// 削除の確認を出し、ユーザーが選ぶまで待つ。確認を待つ依頼が複数あれば、届いた順に 1 件ずつ出す。
  ///
  /// クライアントが接続を閉じて依頼を取り消した (処理のタスクが取り消された) 時は、確認の画面から外して拒否する。
  func confirmSnippetDeletion(request: SnippetDeletionRequest) async -> Bool {
    let requestID = request.id
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        pendingDeletions.append(PendingSnippetDeletion(request: request, continuation: continuation))
        showDeletionConfirmationPanel()
      }
    } onCancel: {
      // 取り消しはほかのスレッドから届くため、確認を待つ依頼を触るメインアクターへ移ってから拒否する。
      Task { @MainActor [weak self] in
        self?.resolveDeletion(requestID: requestID, isApproved: false)
      }
    }
  }

  /// クライアントが `notifications/cancelled` で取り消した依頼が確認待ちの削除なら、確認の画面から外して拒否する。
  func cancelDeletion(clientID: UUID, rpcRequestID: String) {
    for pendingDeletion in pendingDeletions where pendingDeletion.request.clientID == clientID && pendingDeletion.request.rpcRequestID == rpcRequestID {
      resolveDeletion(requestID: pendingDeletion.request.id, isApproved: false)
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
        // macOS 14 からアプリの前面化 (`NSApp.activate()`) はほかのアプリを使っている間は通らないことがあり、
        // パネルの既定 (アプリが前面でない時は隠す) のままだと確認の画面が出ず、MCP の依頼が待ち続けるため。
        panel.hidesOnDeactivate = false
        let hostingController = NSHostingController(rootView: AgentDeleteConfirmationPanelContent(controller: self))
        // パネルの大きさは、内容の大きさが変わるたびに `resizeDeletionConfirmationPanel(contentSize:)` で合わせるため、SwiftUI に決めさせない。
        hostingController.sizingOptions = []
        // 隠したタイトルバーの高さを安全領域として内容の大きさに足さないため (足すとパネルの下に余白が残る)。
        hostingController.safeAreaRegions = []
        panel.contentViewController = hostingController
        deletionConfirmationPanel = panel
        return panel
      }()
    NSApp.activate()
    if let deletionConfirmationContentSize {
      resizeDeletionConfirmationPanel(contentSize: deletionConfirmationContentSize)
    }
    panel.center()
    panel.makeKeyAndOrderFront(nil)
    // アプリが前面に出なかった時も、ほかのアプリのウィンドウの上に出す。
    panel.orderFrontRegardless()
  }

  /// 削除の確認のパネルの大きさを内容に合わせる。依頼ごとに本文と理由の長さで高さが変わるため、上端の位置を保って高さを変える。
  /// パネルを作った直後の内容の測定は、パネルを `deletionConfirmationPanel` に入れる前に届くことがあるため、測った大きさを持っておき、パネルを出す時にも合わせる。
  func resizeDeletionConfirmationPanel(contentSize: CGSize) {
    deletionConfirmationContentSize = contentSize
    guard let panel = deletionConfirmationPanel, contentSize.width > 0, contentSize.height > 0 else {
      return
    }
    // パネルは内容をタイトルバーの下まで広げている (`.fullSizeContentView`) ため、`frameRect(forContentRect:)` が足すタイトルバーの高さを足さず、内容の大きさをそのままパネルの大きさにする。
    panel.setFrame(
      NSRect(x: panel.frame.minX, y: panel.frame.maxY - contentSize.height, width: contentSize.width, height: contentSize.height),
      display: true
    )
  }
}
