---
status: evaluating        # evaluating | building | launched | pivoting | retiring | retired
decision_date:            # 次の判定日 (YYYY-MM-DD)。公開後に設定する
cycle_days: 14            # 判定の周期 (7 または 14)
veto_wait_hours: 12       # 公開後の無人ループの拒否権の待ち時間 (既定 12)
daily_issue_cap: 3        # 1 日に生成してよい改善 issue の上限 (意味の門。既定 3)
launched_at:              # 公開日 (YYYY-MM-DD)。公開前は空
---

# 方向性: tanzaku

## 仮説

AI エージェントを日常的に使う macOS の開発者は、スニペットが増えると略語を覚えきれずに探せなくなり、AI エージェントにスニペットを触らせたいが誤って消されるのは怖い。グローバルショートカットで開くランチャーの日本語の意味検索と、削除を Touch ID で確認する MCP サーバーを持つ買い切りの Mac App Store アプリにすれば、Dash の snippet の代わりに使われ、買い切りで払われる。

## 判定基準

| 指標 | 計測元 (skill / コマンド) | 継続のしきい値 | 打ち切り条件 | 転換の条件 |
| --- | --- | --- | --- | --- |
| 14 日間のダウンロード数 (Mac App Store 全ストアフロント合計) | `/aso-analytics-explorer` (App Store Connect Analytics Reports API のダウンロード数) | 50 以上 | 2 回連続で 15 未満 | 製品ページの閲覧はあるがダウンロード率が 2% 未満なら、製品ページ (スクリーンショット・説明文) の転換 |
| 14 日間のライセンスの売上 (proceeds) | RevenueCat REST API v2 の `GET /projects/{project_id}/metrics/revenue` (期間指定・revenue の定義に proceeds を指定) | 買い切り 3 本分以上 | 2 回連続で 0 かつダウンロードも 15 未満 | ダウンロード 50 以上で売上 0 が 2 回続いたら、無料枠・価格の転換 |

## 必要な機能

- [ ] スニペットの保存と管理画面 (タイトル・本文・キーワード・タグの一覧・追加・編集・削除)
- [ ] ランチャー: グローバルショートカットで開く検索窓。キーワード・タイトル・本文のあいまい検索と、オンデバイスの意味検索 (日本語を含む)。選んだスニペットはクリップボードへコピーし、ユーザーが許可した時だけ前面のアプリへ直接貼り付ける
- [ ] MCP サーバー: アプリに内蔵した localhost の Streamable HTTP サーバー (トークン認証)。スニペットの検索・取得・追加・更新・削除。削除は Touch ID の確認を挟む (設定で切り替え、既定はオン)
- [ ] 買い切りライセンス: 非消耗型 IAP (RevenueCat)。無料はスニペット 20 件まで、購入で上限なし

## デザインの方向

(関門 2 で決める)

## 決めたこと

| 日付 | 場面 | 決めたこと | 決めた人 |
| --- | --- | --- | --- |
| 2026-09-28 | 立ち上げ | 評価は「条件付きで作る」。作り手の目的は issue の「課金を構築したい」から収益と仮定した (評価レポート: 関門 1 の issue) | agent |
| 2026-09-28 | 立ち上げ | 配布は Mac App Store (App Sandbox)。MCP はアプリ内の localhost Streamable HTTP サーバーで提供し、Claude Code には `claude mcp add --transport http` で登録してもらう (MAS 版の Paste と同じ形。 https://github.com/pasteapp/paste-mcp/blob/main/src/discover.ts ) | agent |
| 2026-09-28 | 立ち上げ | 前面アプリへの直接貼り付け (⌘V の送信) は 2026 年に Guideline 2.4.5 でリジェクトされた報告 ( https://developer.apple.com/forums/thread/820594 ) があるため、クリップボードへのコピーを既定にし、直接貼り付けはユーザーが許可した時だけ使う | agent |
| 2026-09-28 | 立ち上げ | バックエンドを持たず、Firebase (Analytics・Crashlytics) も入れない。計測は App Store Connect と RevenueCat で足りるため。GCP のアラートと Crashlytics のアラート転送は対象外 | agent |

## agent に任せること

- データの持ち方 (保存形式・スキーマ)、意味検索のモデルと集約の方法、MCP のツール設計と認証方式、Touch ID の確認の出し方 (アプリを前面に出して認証するか、削除を保留にしてアプリ内で確定するか)
- 画面の細部・文言・ショートカットの既定のキー
- 上記以外で関門 1〜3 で判断しなかった事項
