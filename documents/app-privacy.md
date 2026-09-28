# App Privacy の回答の根拠

`fastlane/app_privacy_details.json` の回答を決めた根拠。適用 (App Store Connect への反映と publish) は申請時に `/appstore-app-privacy` skill で行う。

| category | purposes | data_protections | 根拠 |
| --- | --- | --- | --- |
| PURCHASE_HISTORY | ANALYTICS, APP_FUNCTIONALITY | DATA_NOT_LINKED_TO_YOU | RevenueCat がライセンスの購入履歴を扱う。RevenueCat 公式 ( https://www.revenuecat.com/docs/platform-resources/apple-platform-resources/apple-app-privacy ) が Analytics と App Functionality を最低要件とする。`Purchases.logIn` でユーザー ID を連携しないため、ユーザーに紐付かない |

## 回答に入れないもの

- スニペットの本文・タグ・設定: Mac のサンドボックスのコンテナにだけ保存し、提供者にも第三者にも送らないため「収集」に当たらない
- MCP で AI エージェントに渡すスニペット: 同じ Mac のクライアントへの受け渡しで、tanzaku のコードが外部へ送信しない。どの AI エージェントを接続するかはユーザーが選ぶ
- Analytics・Crashlytics・広告 SDK: 入れていない (`documents/DIRECTION.md`「決めたこと」)

## 見直す時

- Jev による意味検索 (ユーザーが自分の API キーを入れた時だけ、検索語とスニペットの本文を TypeSafe の API へ送る) を出す時は、`OTHER_USER_CONTENT` と `SEARCH_HISTORY` を APP_FUNCTIONALITY・DATA_NOT_LINKED_TO_YOU で足すかを判断し、この表に根拠を書く
- 分析・クラッシュ収集の SDK を入れる時、RevenueCat にユーザー ID を連携する時
