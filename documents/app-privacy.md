# App Privacy の回答の根拠

`fastlane/app_privacy_details.json` は iOS 版の App Privacy の回答で、その回答を決めた根拠をここに書く。Mac 版は App Store で配布しないため App Privacy の回答を持たない。適用 (App Store Connect への反映と publish) は申請時に `/appstore-app-privacy` skill で行う。

回答は「データの収集なし」(`DATA_NOT_COLLECTED`)。Apple の定義では、収集は「デバイスの外へ送り、提供者または第三者が、リクエストをリアルタイムで処理するのに必要な時間より長くアクセスできる状態にすること」を指す ( https://developer.apple.com/app-store/app-privacy-details/ の「"Collect" refers to transmitting data off the device in a way that allows you and/or your third-party partners to access it for a period longer than what is necessary to service the transmitted request in real time.」)。iOS 版がデバイスの外へ送るデータは、次の理由でどれも収集に当たらない。

| データ | 収集に当たらない理由 |
| --- | --- |
| スニペット・フォルダ・タグ・スニペットグループ (iCloud 同期) | CloudKit のプライベートデータベースに置き、ユーザー本人しかアクセスできず、提供者は見られない ( https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase の「Only the user can access their private database, by default. ... Data in the private database isn't visible in the developer portal.」) |
| ライセンスの購入 (IAP) | StoreKit で購入し、購入状況は端末の購入履歴で確かめる。購入の情報は Apple が扱い、Apple が集めるデータは開発者の回答の対象外 ( https://developer.apple.com/app-store/app-privacy-details/ の「You are not responsible for disclosing data collected by Apple.」) |

## 回答に入れないもの

- 意味検索のベクトル・設定: 端末内にだけ置き、同期もしない
- カスタムキーボードで入力した内容: 保存も送信もしない (`documents/DIRECTION.md`「決めたこと」)
- 問い合わせ: メールで受け付け、アプリに送信フォームを持たない
- Analytics・Crashlytics・広告 SDK: 入れていない (`documents/DIRECTION.md`「決めたこと」)

## 見直す時

- iOS 版に Jev による意味検索 (ユーザーが自分の API キーを入れた時だけ、検索語とスニペットの本文を TypeSafe の API へ送る) を入れる時は、`OTHER_USER_CONTENT` と `SEARCH_HISTORY` を APP_FUNCTIONALITY・DATA_NOT_LINKED_TO_YOU で足すかを判断し、この文書に根拠を書く。プライバシーポリシーの Jev の記載は Mac 版のランチャーだけを対象にしている
- 分析・クラッシュ収集の SDK を入れる時、購入の管理にサーバーや外部サービスを使う時、Mac で買ったライセンスを iOS で有効にするためにライセンスキーを iOS から送る時
