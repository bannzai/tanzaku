/// 意味検索の精度を測るためのスニペット 1 件。値はすべて偽物 (`.claude/rules/snippet-content-handling.md`)。
struct SemanticSearchFixtureSnippet {
  /// スニペットのタイトル。
  var title: String
  /// スニペットの本文。
  var body: String
  /// 目的のスニペットと同じ内容を、タイトル・本文と語が重ならないように言い換えたクエリ。
  var paraphrasedQuery: String
}

/// 意味検索の精度を測るスニペットと、それを言い換えたクエリ。日本語の開発者が保存しそうなコマンド・定型文・AI への指示を混ぜる。
let semanticSearchFixtureSnippets: [SemanticSearchFixtureSnippet] = [
  .init(title: "安全に強制プッシュ", body: "git push --force-with-lease origin HEAD", paraphrasedQuery: "リモートのブランチを上書きして送る"),
  .init(title: "使っていない Docker イメージを消す", body: "docker image prune -a -f", paraphrasedQuery: "不要なコンテナの像を掃除する"),
  .init(title: "API トークンの環境変数", body: "export API_TOKEN=dummy-token-for-test", paraphrasedQuery: "認証用の鍵をシェルに設定する"),
  .init(title: "レビュー依頼の定型文", body: "レビューをお願いします。変更点は PR の説明にまとめています。", paraphrasedQuery: "コードを見てもらう時のお願いの文章"),
  .init(title: "会議の日程調整", body: "来週のご都合のよい日時を 3 つほど教えていただけますか。", paraphrasedQuery: "打ち合わせの候補日を相手に尋ねるメール"),
  .init(title: "お礼のあいさつ", body: "先日はお時間をいただきありがとうございました。", paraphrasedQuery: "感謝を伝える一文"),
  .init(title: "SSH でステージングに入る", body: "ssh deploy@staging.example.com", paraphrasedQuery: "検証環境のサーバーにログインする"),
  .init(title: "ポートを使っているプロセスを探す", body: "lsof -i :3000", paraphrasedQuery: "どのプログラムが通信の番号を占有しているか調べる"),
  .init(title: "Xcode の DerivedData を消す", body: "rm -rf ~/Library/Developer/Xcode/DerivedData", paraphrasedQuery: "ビルドのキャッシュを削除する"),
  .init(title: "Node のバージョン確認", body: "node --version", paraphrasedQuery: "JavaScript の実行環境の版を見る"),
  .init(title: "npm のパッケージを入れ直す", body: "rm -rf node_modules && npm ci", paraphrasedQuery: "依存ライブラリをきれいに再インストールする"),
  .init(title: "直前のコミットを取り消す", body: "git reset --soft HEAD~1", paraphrasedQuery: "最後の変更の記録をなかったことにする"),
  .init(title: "ブランチを更新日順に並べる", body: "git branch --sort=-committerdate", paraphrasedQuery: "最近触った作業の枝から一覧にする"),
  .init(title: "JSON を整形して表示", body: "cat response.json | jq .", paraphrasedQuery: "API の返り値を見やすくする"),
  .init(
    title: "SQL で重複を探す",
    body: "SELECT email, COUNT(*) FROM users GROUP BY email HAVING COUNT(*) > 1;",
    paraphrasedQuery: "同じメールアドレスが複数ある利用者を調べるクエリ"
  ),
  .init(title: "AI への指示: テストを書く", body: "この関数のユニットテストを、境界値と異常系を含めて書いてください。", paraphrasedQuery: "試験のコードを作らせるプロンプト"),
  .init(title: "AI への指示: 要約", body: "次の文章を 3 行で要約してください。", paraphrasedQuery: "長文を短くまとめてもらう依頼"),
  .init(title: "謝罪の定型文", body: "ご迷惑をおかけして申し訳ございません。", paraphrasedQuery: "お詫びのメッセージ"),
  .init(title: "Kubernetes の Pod 一覧", body: "kubectl get pods -n dummy-namespace", paraphrasedQuery: "クラスタで動いているコンテナを一覧する"),
  .init(title: "ログを追いかける", body: "tail -f /var/log/dummy-app.log", paraphrasedQuery: "出力され続ける記録をリアルタイムで見る"),
  .init(title: "日時を ISO 8601 で出す", body: "date -u +\"%Y-%m-%dT%H:%M:%SZ\"", paraphrasedQuery: "今の時刻を標準形式の文字列にする"),
  .init(title: "Homebrew を更新", body: "brew update && brew upgrade", paraphrasedQuery: "Mac のパッケージ管理ツールで全部を最新にする"),
  .init(title: "休暇の連絡", body: "明日は休暇をいただきます。急ぎの件はチャットでご連絡ください。", paraphrasedQuery: "休みを取ることをチームに伝える"),
  .init(title: "Wi-Fi のパスワードを表示", body: "security find-generic-password -wa dummy-network", paraphrasedQuery: "無線 LAN の暗証番号を確認するコマンド"),
  .init(
    title: "Create a Python virtual environment",
    body: "python3 -m venv .venv && source .venv/bin/activate",
    paraphrasedQuery: "set up an isolated python sandbox"
  ),
  .init(
    title: "Out of office reply",
    body: "I am away until Monday and will reply when I return.",
    paraphrasedQuery: "automatic message while on vacation"
  ),
]

/// fixture のどのスニペットとも関係の無いクエリ。意味検索の最低の類似度を決めるため、関係の無いクエリの類似度を測るのに使う。
let semanticSearchFixtureUnrelatedQueries = [
  "明日の天気は晴れるかな",
  "近所のおいしいラーメン屋",
  "猫の写真を見たい",
  "what should I cook for dinner",
]
