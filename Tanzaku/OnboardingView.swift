import SwiftData
import SwiftUI
import TanzakuKit

/// 初回起動の 3 つの手順 (`documents/design/Onboarding.dc.html`)。ランチャーを開くキー・最初のスニペット・AI エージェントの接続を順に案内する。
struct OnboardingView: View {
  /// 最初のスニペットを保存した後に呼ぶ。ランチャーの意味検索のベクトルを作り直す。
  let onSnippetsChange: () -> Void
  /// 最後の手順で「はじめる」か「スキップ」を押した時に呼ぶ。初回起動を終えてウィンドウを閉じる。
  let onFinish: () -> Void

  @Environment(\.modelContext) private var modelContext
  /// 表示している手順。
  @State private var step = OnboardingStep.launcherShortcut
  /// 最初のスニペットのタイトルの入力。
  @State private var title = ""
  /// 最初のスニペットのキーワードの入力。
  @State private var keyword = ""
  /// 最初のスニペットの本文の入力。
  @State private var bodyText = ""
  /// 保存した最初のスニペット。「戻る」で入力を直してもう一度「次へ」を押した時に、2 つ目を作らずこれを書き換える。
  @State private var savedSnippet: Snippet?
  /// 最初のスニペットを保存できなかった理由。
  @State private var errorMessage: String?

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 28) {
        ForEach(OnboardingStep.allCases, id: \.self) { indicatorStep in
          VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
              .fill(indicatorStep.rawValue <= step.rawValue ? onboardingStepColor(step: indicatorStep) : LauncherColors.line)
              .frame(width: 140, height: 5)
            Text(onboardingStepLabel(step: indicatorStep))
              .font(.system(size: 12, weight: indicatorStep == step ? .bold : .regular))
              .foregroundStyle(indicatorStep == step ? LauncherColors.foreground : LauncherColors.tertiaryForeground)
          }
        }
      }
      .padding(.top, 4)

      Group {
        switch step {
        case .launcherShortcut:
          OnboardingLauncherShortcutStep()
        case .firstSnippet:
          firstSnippetStep
        case .agentConnection:
          OnboardingAgentConnectionStep()
        }
      }
      .padding(.horizontal, 96)
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      Divider()
      HStack(spacing: 10) {
        Button("Skip") {
          move(destination: onboardingSkipDestination(step: step))
        }
        .buttonStyle(.plain)
        .foregroundStyle(LauncherColors.secondaryForeground)
        .padding(.horizontal, 10)
        Spacer()
        if let previousStep = onboardingPreviousStep(step: step) {
          Button("Back") {
            errorMessage = nil
            step = previousStep
          }
          .controlSize(.large)
        }
        Button {
          if step == .firstSnippet && !saveFirstSnippet() {
            return
          }
          move(destination: onboardingNextStep(step: step))
        } label: {
          Text(step == .agentConnection ? LocalizedStringKey("Get Started") : LocalizedStringKey("Next"))
            .frame(minWidth: 60)
        }
        // 最初のスニペットの本文は複数行のため、Return を本文の改行に使えるよう、その手順では Return で進めない。
        .keyboardShortcut(step == .firstSnippet ? nil : .defaultAction)
        .buttonStyle(.borderedProminent)
        .tint(LauncherColors.accent)
        .controlSize(.large)
      }
      .padding(.horizontal, 20)
      .frame(height: 60)
    }
    // デザインは 760 x 560 で、上の 40 はウィンドウの閉じるボタンの帯。帯はタイトルバー (安全領域) が受け持つため、内容はその下の高さにする。
    .frame(width: 760, height: 520)
    .background(LauncherColors.panel)
  }

  /// 最初のスニペットの入力 (デザインの 2 つ目の手順)。
  private var firstSnippetStep: some View {
    VStack(spacing: 14) {
      VStack(spacing: 8) {
        Text("Write your first snippet")
          .font(.system(size: 22, weight: .bold))
        Text("Add one piece of text or a command you often type.")
          .font(.system(size: 13))
          .foregroundStyle(LauncherColors.secondaryForeground)
      }
      .multilineTextAlignment(.center)
      Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
        GridRow {
          Text("Title")
            .foregroundStyle(LauncherColors.secondaryForeground)
            .gridColumnAlignment(.trailing)
          TextField("Title", text: $title, prompt: Text("Get a token from an environment variable"))
            .labelsHidden()
        }
        GridRow {
          Text("Keyword")
            .foregroundStyle(LauncherColors.secondaryForeground)
          HStack(spacing: 10) {
            TextField("Keyword", text: $keyword, prompt: Text(verbatim: "envkey"))
              .labelsHidden()
              .frame(width: 140)
            Text("Optional. Snippets can also be found by what the body means")
              .font(.system(size: 12))
              .foregroundStyle(LauncherColors.tertiaryForeground)
          }
        }
        GridRow(alignment: .top) {
          Text("Body")
            .foregroundStyle(LauncherColors.secondaryForeground)
            .padding(.top, 8)
          TextEditor(text: $bodyText)
            .font(.system(size: 12, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(6)
            .frame(height: 96)
            .background(LauncherColors.code, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(LauncherColors.strongLine))
        }
      }
      .font(.system(size: 13))
      .padding(.top, 6)
      if let errorMessage {
        Text(verbatim: errorMessage)
          .font(.system(size: 12))
          .foregroundStyle(.red)
      }
    }
  }

  /// `destination` の手順へ進む。`nil` なら初回起動を終える。
  private func move(destination: OnboardingStep?) {
    errorMessage = nil
    guard let destination else {
      onFinish()
      return
    }
    step = destination
  }

  /// 入力した最初のスニペットを保存し、進めてよければ `true` を返す。何も入力していなければ保存せずに進める。
  ///
  /// 保存は管理ウィンドウの編集と同じく `applySnippetEdit` の検査を通した時だけにし、通らなければ理由を出して手順に留まる。
  private func saveFirstSnippet() -> Bool {
    guard [title, keyword, bodyText].contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
      return true
    }
    let snippet = savedSnippet ?? Snippet(body: "")
    do {
      try applySnippetEdit(
        snippet: snippet,
        body: bodyText,
        title: title,
        keyword: keyword,
        language: nil,
        color: nil,
        folder: nil,
        tagNames: [],
        modelContext: modelContext,
        now: .now
      )
      if let saveErrorMessage = saveManagerChanges(modelContext: modelContext) {
        errorMessage = saveErrorMessage
        return false
      }
      savedSnippet = snippet
      onSnippetsChange()
      errorMessage = nil
      return true
    } catch let validationError as SnippetValidationError {
      errorMessage = validationError.description
      return false
    } catch {
      // ストアの読み込みの失敗は書き込みの途中で起き得るため、途中まで書き込んだ変更と新規の挿入を取り消す。
      modelContext.rollback()
      errorMessage = error.localizedDescription
      return false
    }
  }
}

/// 手順の帯の色。デザインは手順ごとにスニペットの色の朱・藍・松葉を使う。
func onboardingStepColor(step: OnboardingStep) -> Color {
  switch step {
  case .launcherShortcut:
    snippetBandColor(snippetColor: .shu)
  case .firstSnippet:
    snippetBandColor(snippetColor: .ai)
  case .agentConnection:
    snippetBandColor(snippetColor: .matsuba)
  }
}

/// 手順の帯の下の名前。
func onboardingStepLabel(step: OnboardingStep) -> LocalizedStringKey {
  switch step {
  case .launcherShortcut:
    "Shortcut"
  case .firstSnippet:
    "First snippet"
  case .agentConnection:
    "AI agents"
  }
}

/// ランチャーを開くキーの手順 (デザインの 1 つ目の手順)。
private struct OnboardingLauncherShortcutStep: View {
  @Environment(LauncherShortcutController.self) private var launcherShortcutController

  var body: some View {
    VStack(spacing: 16) {
      Text("Choose the key that opens the launcher")
        .font(.system(size: 22, weight: .bold))
      Text("From any app, this key opens the launcher in the center of the screen.\nType to search, press Return to copy, and Esc to close.")
        .font(.system(size: 13))
        .foregroundStyle(LauncherColors.secondaryForeground)
        .lineSpacing(4)
      HStack(spacing: 8) {
        if launcherShortcutController.isRecording {
          Text("Press the new shortcut")
            .font(.system(size: 14))
            .foregroundStyle(LauncherColors.secondaryForeground)
            .frame(height: 36)
        } else if let launcherShortcut = launcherShortcutController.launcherShortcut {
          ForEach(Array(launcherShortcutKeyLabels(launcherShortcut: launcherShortcut).enumerated()), id: \.offset) { index, label in
            if index > 0 {
              Text(verbatim: "+")
                .font(.system(size: 14))
                .foregroundStyle(LauncherColors.tertiaryForeground)
            }
            ShortcutKeyCap(label: label, fontSize: 16, height: 36)
          }
        } else {
          Text("No shortcut")
            .font(.system(size: 14))
            .foregroundStyle(LauncherColors.secondaryForeground)
            .frame(height: 36)
        }
      }
      .padding(.vertical, 14)
      .padding(.horizontal, 20)
      .background(LauncherColors.footer, in: RoundedRectangle(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(LauncherColors.strongLine))
      .padding(.top, 10)
      Button(launcherShortcutController.isRecording ? LocalizedStringKey("Cancel") : LocalizedStringKey("Record another key")) {
        if launcherShortcutController.isRecording {
          launcherShortcutController.cancelRecording()
        } else {
          launcherShortcutController.startRecording()
        }
      }
      .buttonStyle(.plain)
      .foregroundStyle(LauncherColors.accentText)
      if let errorMessage = launcherShortcutController.errorMessage {
        Text(verbatim: errorMessage)
          .font(.system(size: 12))
          .foregroundStyle(.red)
      }
    }
    .multilineTextAlignment(.center)
    .onDisappear {
      launcherShortcutController.cancelRecording()
    }
  }
}

/// AI エージェントの接続の手順 (デザインの 3 つ目の手順)。コマンドとトークンは設定の「AI エージェント」と同じものを出す。
private struct OnboardingAgentConnectionStep: View {
  @Environment(MCPServerController.self) private var mcpServerController

  var body: some View {
    VStack(spacing: 14) {
      VStack(spacing: 8) {
        Text("Connect your AI agents")
          .font(.system(size: 22, weight: .bold))
        Text("Claude Code can search, add, and organize your Tanzaku snippets.\nDeletions from AI agents are confirmed with Touch ID every time.")
          .font(.system(size: 13))
          .foregroundStyle(LauncherColors.secondaryForeground)
          .lineSpacing(4)
      }
      .multilineTextAlignment(.center)
      VStack(alignment: .leading, spacing: 8) {
        Text("Command to run in Terminal")
          .font(.system(size: 12))
          .foregroundStyle(LauncherColors.secondaryForeground)
        HStack(spacing: 10) {
          Text(mcpAddCommand(token: mcpServerController.unboundToken.map { maskedMCPAccessToken(token: $0) } ?? "…"))
            .font(.system(size: 12, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LauncherColors.code, in: RoundedRectangle(cornerRadius: 6))
          Button("Copy") {
            copyToPasteboard(text: mcpAddCommand(token: mcpServerController.unboundToken ?? ""))
          }
          .disabled(mcpServerController.unboundToken == nil)
        }
      }
      .padding(.vertical, 14)
      .padding(.horizontal, 16)
      .background(LauncherColors.footer, in: RoundedRectangle(cornerRadius: 9))
      .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(LauncherColors.strongLine))
      .padding(.top, 6)
      if let tokenErrorMessage = mcpServerController.tokenErrorMessage {
        Text(verbatim: tokenErrorMessage)
          .font(.system(size: 12))
          .foregroundStyle(.red)
      }
      Text("You can also connect later in Settings › AI Agents")
        .font(.system(size: 12))
        .foregroundStyle(LauncherColors.tertiaryForeground)
    }
  }
}
