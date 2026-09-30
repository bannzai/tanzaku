# AGENTS.md

## 要件と方向性

- `documents/PROJECT.md` が要件 (機能・対象外・設計上の決定) の正。機能を足す・変える前に読む
- `documents/DIRECTION.md` が判断の根拠 (仮説・判定基準・決めたこと・agent に任せること)。ここに無い問いは「agent に任せること」に従って決め、「決めたこと」に追記する

## 検証方法

開発者のローカル Mac の負荷を避けるため、ビルド・テスト・画面の確認は外部のマシンで行う。ローカルでの `xcodebuild` やアプリの起動は既定にしない。issue や手順書にローカル前提の記述 (`make build-macos`、アプリの起動手順) があっても、それだけではローカルで実行する理由にしない。

| 確認すること | 既定の実行先 (public リポジトリ) | private / internal に変わった場合 |
| --- | --- | --- |
| ビルドとユニットテスト | GitHub Actions の `.github/workflows/ci.yml` (`macos-26` ランナーで `make build-macos`・`make build-ios`・`make test`)。ブランチを push し、`gh pr checks <PR 番号>` と失敗時の `gh run view <run ID> --log-failed` で結果を見る | GitHub-hosted の macOS ランナーが課金対象になるため、Devin の macOS セッション (`/devin-macos-e2e` skill) で行う |
| macOS アプリの画面・挙動 | simtunnel (`/macos-simtunnel` skill)。GitHub Actions の macOS ランナーのデスクトップでアプリを動かし、tailnet 経由で操作・撮影する | Devin の macOS セッション (`/devin-macos-e2e` skill) |
| iOS アプリの画面・挙動 | simtunnel (`/ios-simulator` skill)。GitHub Actions の macOS ランナーの iOS Simulator でアプリを動かし、tailnet 経由で操作・撮影する | Devin の macOS セッション (`/devin-macos-e2e` skill) |
| 公開サイト (`docs/` の LP・法務ドキュメント) の表示 | webtunnel (`/webtunnel` skill)。GitHub Actions の Linux ランナーの Chromium で `docs/` を開く | 同じ (webtunnel は caller リポジトリの visibility を問わない) |

### Makefile

| コマンド | 内容 |
| --- | --- |
| `make build-macos` | macOS アプリのビルド (`-derivedDataPath tmp/DerivedData`) |
| `make build-ios` | iOS アプリのシミュレータ向けのビルド |
| `make test` | macOS アプリと `TanzakuKit` のユニットテスト (Swift Testing) |
| `make macos` | Release ビルドを `/Applications/Tanzaku.app` に配置する。開発者が普段使いする時の手段で、agent の検証手段ではない |
| `make clean` | `tmp/DerivedData` を消す |

CI はランナーに署名 ID が無いため `SIGNING_FLAGS` を ad-hoc 署名で上書きする (`.github/workflows/ci.yml`)。

### 画面の確認

- 検証するブランチを先に push する。セッションは `--ref` のブランチの push 済みの先端をビルドし、`--ref` を省くと `main` をビルドする
- macOS アプリ: `SIMTUNNEL_REPO=bannzai/tanzaku SIMTUNNEL_WORKFLOW=macos-app-session.yml ~/ghq/github.com/bannzai/simtunnel/local/simtunnel up <セッション名> --ref <ブランチ> --wait` で `.github/workflows/macos-app-session.yml` を起動し、`/macos-simtunnel` skill の `scripts/macos-wda.sh` で操作・撮影する。runner には署名 ID が無いため `DebugUnsigned` 構成 (署名しない Debug) をビルドする
- iOS アプリ: `SIMTUNNEL_REPO=bannzai/tanzaku ~/ghq/github.com/bannzai/simtunnel/local/simtunnel up <セッション名> --ref <ブランチ> --device <デバイス名> --wait` で `.github/workflows/simulator-session.yml` を起動し、`/ios-simulator` skill の `scripts/ios-wda.sh --session <セッション名>` で操作・撮影する。iPhone は既定の `iPhone 17`、iPad は `--device 'iPad Pro 11-inch (M5)'` を渡す。runner には署名 ID が無いため `DebugUnsigned` 構成をビルドする。ローカル sim-boot に倒してよい条件は `/ios-simulator` skill Phase 1 に従い、倒した理由を完了報告に書く
- 公開サイト: `WEBTUNNEL_REPO=bannzai/tanzaku ~/ghq/github.com/bannzai/webtunnel/local/webtunnel up <セッション名> --ref <ブランチ> --wait` で `.github/workflows/browser-session.yml` を起動し、`/webtunnel` skill の手順で agent-browser から操作・撮影する
- セッション名は `tanzaku-<worktree 名>` (macOS アプリは末尾に `-mac`、iOS アプリは `-ios`、公開サイトは `-web`)。セッション名は tailnet のホスト名になり、別リポジトリのセッションと衝突させない
- 確認が終わったら `up` と同じ環境変数で `down <セッション名>` を実行して閉じる。macOS ランナーの並列数は CI と共有する
- 到達しにくい状態 (課金状態・大量のスニペット・認証の失敗) は Debug ビルドの開発者メニューで作る。iOS アプリの開発者メニューは一覧の右上のメニューにあり、見本のスニペットの投入・全削除・ライトとダークの切り替えを持つ。ロケールの切り替えのように起動前に効かせる設定は `macos-wda.sh session` / `ios-wda.sh launch` の `--arg` (例: `--arg -AppleLanguages --arg '(ja)'`) で渡す

### ローカルで実行してよい場合

次のどれかに当たり、GitHub Actions (CI・simtunnel・webtunnel) では確認が成立しない時だけローカルでビルド・起動する。当たる時も、実行の直前に CPU 使用率を `top -l 2 -n 0 -s 1` の 2 回目の `CPU usage` の行で確かめ、idle が 50% 未満なら実行せず、負荷が下がるのを待つか外部のマシンで確認できる方法に切り替える。この Mac は他のプロジェクトの作業者・Simulator と CPU を分け合っており、idle が半分を切った状態で `xcodebuild` やアプリの起動を足すと開発者の操作が止まるため (2026-09-28 に load average 125 の状態で bannzai から指摘を受けた)。ローカルで実行した時は、当たった理由と実行直前の idle を完了報告に書く。

- 外部のマシンで確認が成立しない (Touch ID の実機認証、ローカルにしか無い Claude Code / Claude Desktop からの MCP 接続、アクセシビリティ権限を与えた状態の貼り付け)
- simtunnel / webtunnel の導入が完了していない (Secrets の `TS_OIDC_CLIENT_ID` / `TS_OIDC_AUDIENCE` が未登録)、tailnet に接続できない、macOS ランナーの並列上限に達している
- private / internal のリポジトリで Devin が使えない・使用量が尽きた

## Xcode プロジェクト

- `Tanzaku.xcodeproj` がプロジェクト構成の唯一の正。変更は Xcode の GUI か `project.pbxproj` の直接編集で行う
- `xcodegen generate` を実行しない。`project.yml` をリポジトリに置かない。機械検査は `~/.agents/skills/create-new-app/scripts/check-setup.sh` の `xcode-project-source` 項目

<!-- ai-review-config begin -->
<!--
このブロックは自動生成です。直接編集せず、テンプレートを更新してから再生成してください。
内容は AI コードレビュー時の挙動指示であり、コードベース自体への規約ではありません。
-->

## レビュー時の応答スタイル

- 応答は日本語で行う

## レビュー範囲外

以下は自動レビューで指摘しない (別の検出経路があるため):

- コンパイルエラー・型エラー (ローカル/CI のビルドで検出される)
- Lint/フォーマット違反 (リンター・フォーマッターで検出される)
<!-- ai-review-config end -->
