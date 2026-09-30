import SwiftData
import SwiftUI
import TanzakuKit

/// キーボードのスニペットの一覧。検索の入力が空なら更新日時の新しい順にすべて、入力があれば検索の結果を出す。
///
/// 検索は文字列の一致だけにし、意味検索は使わない。埋め込みモデルの用意に数秒かかり、キーボードの拡張はメモリの上限が小さいため (`documents/DIRECTION.md`「決めたこと」)。
struct KeyboardSnippetList: View {
  /// 検索の入力。
  var searchQuery: String
  /// スニペットを選んだ。
  var onSelect: (Snippet) -> Void

  /// すべてのスニペット。更新日時の新しい順 (iOS 本体の一覧と同じ)。
  @Query(sort: \Snippet.updatedAt, order: .reverse) private var snippets: [Snippet]
  /// 検索に使う。
  @Environment(\.modelContext) private var modelContext

  var body: some View {
    // 検索に失敗した時 (ストアの読み込みの失敗) は、誤った結果を出さないよう空の一覧にする (iOS 本体の一覧と同じ)。
    let listedSnippets = (try? filteredSnippets(query: searchQuery, filter: .all, snippets: snippets, modelContext: modelContext, embedder: nil)) ?? []
    if listedSnippets.isEmpty {
      // ContentUnavailableView は大きな文字で組まれ、キーボードの低い欄では切れるため、小さな文字で並べる。
      VStack(spacing: 4) {
        if searchQuery.isEmpty {
          Text("No Snippets")
            .font(.subheadline.weight(.semibold))
          Text("Add snippets in the Tanzaku app")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          Text("No Results")
            .font(.subheadline.weight(.semibold))
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      KeyboardSnippetRows(snippets: listedSnippets, onSelect: onSelect)
    }
  }
}

/// スニペットグループのメニュー。グループに登録した順にスニペットを出す (Mac のメニューと同じ)。
struct KeyboardSnippetGroupMenu: View {
  /// メニューを出すスニペットグループ。
  var snippetGroup: SnippetGroup
  /// スニペットを選んだ。
  var onSelect: (Snippet) -> Void

  var body: some View {
    KeyboardSnippetRows(snippets: snippetGroupMenuSnippets(snippetGroup: snippetGroup), onSelect: onSelect)
  }
}

/// ストアを開けなかった・読めなかった時に、スニペットの一覧の代わりに出す案内。文字のキーはこの間も使える。
///
/// フルアクセスが無い時はフルアクセスの許可の手順を出す。キーボードの拡張からは設定のアプリを開けないため、手順を文字で出す。
struct KeyboardStoreUnavailableView: View {
  /// ユーザーがフルアクセスを許可したか。
  var hasFullAccess: Bool
  /// ストアを開けなかった・読めなかった理由。
  var error: any Error

  var body: some View {
    ScrollView {
      VStack(spacing: 6) {
        if hasFullAccess {
          Text("Could not open snippets")
            .font(.subheadline.weight(.semibold))
        } else {
          Text("Allow Full Access to insert snippets")
            .font(.subheadline.weight(.semibold))
          Text("Settings > General > Keyboard > Keyboards > Tanzaku > Allow Full Access")
            .font(.caption)
          Text("Typing works without Full Access. Tanzaku never saves or sends what you type.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Text(verbatim: String(describing: error))
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .multilineTextAlignment(.center)
      .padding(12)
      .frame(maxWidth: .infinity)
    }
  }
}

/// スニペットの行を縦に並べる。行をタップするとそのスニペットを選ぶ。
private struct KeyboardSnippetRows: View {
  /// 並べるスニペット。
  var snippets: [Snippet]
  /// スニペットを選んだ。
  var onSelect: (Snippet) -> Void

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(snippets) { snippet in
          Button {
            onSelect(snippet)
          } label: {
            KeyboardSnippetRow(snippet: snippet)
          }
          .buttonStyle(.plain)
          Divider()
            .padding(.leading, 12)
        }
      }
    }
  }
}

/// スニペットの 1 行。色の帯・名前・本文の 1 行目を並べる (iOS 本体の一覧の行を、キーボードの狭い欄に合わせて日付とキーワードを省いたもの)。
private struct KeyboardSnippetRow: View {
  /// 行のスニペット。
  var snippet: Snippet

  var body: some View {
    HStack(spacing: 10) {
      SnippetColorBand(snippet: snippet)
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: snippetDisplayTitle(snippet: snippet))
          .font(.subheadline.weight(.semibold))
        Text(verbatim: snippetBodyFirstLine(body: snippet.body))
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
      }
      .lineLimit(1)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .frame(minHeight: 44)
    .contentShape(Rectangle())
  }
}
