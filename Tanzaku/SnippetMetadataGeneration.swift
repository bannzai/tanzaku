import Foundation
import SwiftData
import TanzakuKit
import os

#if canImport(FoundationModels)
  import FoundationModels
#endif

/// 設定の「一般」の「タイトルを自動で付ける」を入れる `UserDefaults` のキー。設定の「一般」(`GeneralSettingsView`) が書き込み、スニペットの編集画面は読むだけ。
let snippetTitleGenerationEnabledUserDefaultsKey = "snippetTitleGenerationEnabled"
/// 設定の「一般」の「タグを自動で付ける」を入れる `UserDefaults` のキー。設定の「一般」(`GeneralSettingsView`) が書き込み、スニペットの編集画面は読むだけ。
let snippetTagGenerationEnabledUserDefaultsKey = "snippetTagGenerationEnabled"

/// 「タイトルを自動で付ける」の既定。issue #55 の「タイトルはデフォルト ON」(`documents/DIRECTION.md`「決めたこと」)。
let isSnippetTitleGenerationEnabledByDefault = true
/// 「タグを自動で付ける」の既定。issue #55 の「タグはデフォルト OFF」(`documents/DIRECTION.md`「決めたこと」)。
let isSnippetTagGenerationEnabledByDefault = false

/// 言語モデルに渡す本文の最大の文字数。これより長い本文は先頭だけを渡す。
///
/// 端末内の言語モデルが 1 回のやり取りで扱えるのは 4096 トークン ( https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window )。
/// 日本語は 1 文字が 1 トークンを超えることがあるため、指示と応答の分を残して収まる文字数にする。タイトルとタグは本文の先頭から決められる。
private let snippetMetadataGenerationBodyMaxLength = 1500

/// タイトル・タグの自動の作成の失敗の記録。スニペットの本文と言語モデルの応答は入れない (`.claude/rules/snippet-content-handling.md`)。
private let snippetMetadataGenerationLogger = Logger(subsystem: "com.bannzai.tanzaku", category: "SnippetMetadataGeneration")

/// 設定で「タイトルを自動で付ける」がオンか。設定を変えていなければ既定 (`isSnippetTitleGenerationEnabledByDefault`)。
func isSnippetTitleGenerationEnabled(userDefaults: UserDefaults) -> Bool {
  userDefaults.object(forKey: snippetTitleGenerationEnabledUserDefaultsKey) as? Bool ?? isSnippetTitleGenerationEnabledByDefault
}

/// 設定で「タグを自動で付ける」がオンか。設定を変えていなければ既定 (`isSnippetTagGenerationEnabledByDefault`)。
func isSnippetTagGenerationEnabled(userDefaults: UserDefaults) -> Bool {
  userDefaults.object(forKey: snippetTagGenerationEnabledUserDefaultsKey) as? Bool ?? isSnippetTagGenerationEnabledByDefault
}

/// 端末内の言語モデル (Apple Intelligence の Foundation Models) を今使えるか。macOS 26 より前・Apple Intelligence に対応しない Mac・Apple Intelligence がオフ・モデルの用意が済んでいない時は `false`。
func isSnippetMetadataGenerationAvailable() -> Bool {
  #if canImport(FoundationModels)
    if #available(macOS 26.0, *) {
      return SystemLanguageModel.default.isAvailable
    }
  #endif
  return false
}

/// 端末内の言語モデルに `instructions` と `prompt` を渡し、応答の文字列を返す。言語モデルが無い OS では `nil`。
///
/// 本文は端末内の言語モデルにだけ渡し、端末の外へ送らない (`documents/DIRECTION.md`「決めたこと」)。
/// Foundation Models は Private Cloud Compute のモデルも扱うため、端末内のモデル (`SystemLanguageModel`。 https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel ) を明示して渡す。
/// 冪等ではない: 同じ入力でも応答は呼ぶたびに変わり得る。
private func languageModelResponse(instructions: String, prompt: String) async throws -> String? {
  #if canImport(FoundationModels)
    if #available(macOS 26.0, *) {
      return try await LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions).respond(to: prompt).content
    }
  #endif
  return nil
}

/// 編集を終えたスニペットに、設定でオンにした自動のタイトル・タグを付けて保存する。どちらかを付けたら `true`。
///
/// タイトルはタイトルが無い時、タグはタグが 1 つも無い時だけ作る。言語モデルを使えない時・作るのに失敗した時は何も付けない (失敗は記録だけにする。タイトルとタグは無くても使え、次に編集を終えた時にまた試すため)。
/// 応答を待つ間にスニペットが消された時は何もしない。
/// 冪等ではない: 言語モデルの応答は呼ぶたびに変わり得る。ただしタイトル・タグを付けた後は、もう一度呼んでも付け直さない。
func generateSnippetMetadata(snippet: Snippet, userDefaults: UserDefaults, modelContext: ModelContext) async -> Bool {
  guard isSnippetMetadataGenerationAvailable(), isSnippetInStore(snippet: snippet) else {
    return false
  }
  let sourceBody = snippet.body
  var isSnippetChanged = false
  if isSnippetTitleGenerationEnabled(userDefaults: userDefaults) && snippet.title == nil {
    do {
      let generatedText = try await languageModelResponse(
        instructions:
          "You write a title for a text snippet, which is reusable text, a shell command, code, or a prompt. Reply with the title only, on one line, without quotes or a trailing period. Write the title in the same language as the snippet. Keep it within \(generatedSnippetTitleMaxLength) characters.",
        prompt: String(sourceBody.prefix(snippetMetadataGenerationBodyMaxLength))
      )
      if let generatedText, isSnippetInStore(snippet: snippet) {
        isSnippetChanged = applyGeneratedSnippetTitle(snippet: snippet, generatedText: generatedText, sourceBody: sourceBody)
      }
    } catch {
      snippetMetadataGenerationLogger.error("Failed to generate a title: \(String(describing: type(of: error)), privacy: .public)")
    }
  }
  if isSnippetTagGenerationEnabled(userDefaults: userDefaults) && isSnippetInStore(snippet: snippet) && (snippet.tags ?? []).isEmpty {
    do {
      let generatedText = try await languageModelResponse(
        instructions:
          "You choose tags for a text snippet, which is reusable text, a shell command, code, or a prompt. Reply with up to \(generatedSnippetTagLimit) tags separated by commas, and nothing else. Each tag is one or two words. When an existing tag fits, use it as written.",
        prompt:
          "Existing tags: \(modelContext.fetch(FetchDescriptor<Tag>()).map(\.name).sorted().joined(separator: ", "))\n\nSnippet:\n\(sourceBody.prefix(snippetMetadataGenerationBodyMaxLength))"
      )
      if let generatedText, isSnippetInStore(snippet: snippet) {
        isSnippetChanged =
          try applyGeneratedSnippetTags(snippet: snippet, generatedText: generatedText, sourceBody: sourceBody, modelContext: modelContext)
          || isSnippetChanged
      }
    } catch {
      snippetMetadataGenerationLogger.error("Failed to generate tags: \(String(describing: type(of: error)), privacy: .public)")
    }
  }
  guard isSnippetChanged else {
    return false
  }
  if let saveErrorMessage = saveManagerChanges(modelContext: modelContext) {
    snippetMetadataGenerationLogger.error("Failed to save the generated title and tags: \(saveErrorMessage, privacy: .public)")
    return false
  }
  return true
}
