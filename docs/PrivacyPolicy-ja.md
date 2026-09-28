# プライバシーポリシー

bannzai（以下「提供者」といいます。）は、提供者の提供するアプリ「Tanzaku」（macOS アプリ、ならびに iOS アプリおよびその共有シート・キーボード・ショートカット等の拡張機能をいい、以下あわせて「本サービス」といいます。）における、ユーザーについての個人情報を含む利用者情報の取扱いについて、以下のとおりプライバシーポリシー（以下「本ポリシー」といいます。）を定めます。

## 収集する利用者情報および収集方法

本ポリシーにおいて、「利用者情報」とは、ユーザーの識別に係る情報、通信サービス上の行動履歴、その他ユーザーまたはユーザーの端末に関連して生成または蓄積された情報であって、本ポリシーに基づき提供者が収集するものを意味するものとします。

### ユーザーが入力する情報（端末とユーザー自身の iCloud に保存されます）

本サービスでユーザーが登録するスニペット（タイトル・本文・キーワード・タグ・フォルダ・スニペットグループ）と設定は、ユーザーの端末内に保存され、**提供者のサーバーに送信されません**。提供者はこれらの情報を収集・閲覧できません。

ユーザーが iCloud を利用している場合、スニペット・フォルダ・タグ・スニペットグループは、Mac と iOS の間で同期するため、Apple Inc. が提供する iCloud のユーザー自身の領域（CloudKit のプライベートデータベース）に保存されます。この領域はユーザー本人だけがアクセスでき、提供者は閲覧できません。iCloud に保存された情報は Apple Inc. のプライバシーポリシー（ https://www.apple.com/jp/legal/privacy/ ）に従って扱われます。
<!-- source: https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase 「Only the user can access their private database, by default. They own all of the database's content and can view and modify that content. Data in the private database isn't visible in the developer portal.」 -->

スニペットの検索（意味検索を含む）は端末内で行われ、スニペットの内容を外部へ送信しません。意味検索のためのデータは各端末内で作成し、同期しません。

- スニペットのバックアップはユーザー自身の責任で行っていただきます。端末の変更・初期化、本サービスの削除、iCloud からのデータの削除によりスニペットが失われた場合、提供者は復旧できません

### キーボードで入力する内容（iOS）

本サービスの iOS のキーボードで入力した文字は、保存も送信もしません。キーボードは、スニペットを読み取って入力欄へ挿入するためだけに使います。

### キー入力の監視（Mac のスニペットグループ）

Mac 版は、スニペットグループのキーワードを判定するため、ユーザーが許可した場合に限りキー入力を監視し、入力欄のキャレットの位置をアクセシビリティの機能で取得します。監視したキー入力はキーワードの判定だけに使い、保存も送信もしません。

### AI エージェントとの連携（MCP、Mac のみ）

本サービスの Mac 版は、ユーザーが接続した AI エージェント（Claude Code 等）からスニペットを検索・追加・更新・削除できるよう、Model Context Protocol（MCP）のサーバーを Mac 内で動かします。このサーバーは同じ Mac（127.0.0.1）からの接続だけを受け付け、本サービスが発行するトークンを持つクライアントだけが利用できます。

ユーザーが接続した AI エージェントに渡したスニペットは、その AI エージェントの提供元の規約・プライバシーポリシーに従って扱われます。どの AI エージェントを接続するかはユーザーが選び、本サービスの設定で接続を取り消せます。

### ライセンスの購入と確認

**Mac 版**は、Lemon Squeezy（米国）を通じてライセンスを販売します。決済は Lemon Squeezy が販売代行者（Merchant of Record）として処理し、購入時に入力する氏名・メールアドレス・決済情報は Lemon Squeezy が取得します。提供者はクレジットカード番号等の決済情報を受け取りません。提供者は Lemon Squeezy から購入者の氏名・メールアドレスと注文の内容（購入した商品・日時・金額等）を受け取ります。Lemon Squeezy が取得した情報は Lemon Squeezy のプライバシーポリシー（ https://www.lemonsqueezy.com/privacy ）に従って扱われます。
<!-- source: https://www.lemonsqueezy.com/buyer-terms 「As merchant of record, Lemon Squeezy is an authorized reseller of the product for the Supplier and provides merchant services to facilitate transactions.」 / 同ページのフッター「Sold through Link, LLC f/k/a Lemon Squeezy LLC」 / https://docs.lemonsqueezy.com/api/orders/the-order-object の注文オブジェクトに user_name (The full name of the customer.) と user_email (The email address of the customer.) がある -->

ライセンスの有効化・確認・解除のため、本サービスは Lemon Squeezy の API へ、ライセンスキーと、ライセンスを有効にした Mac を区別するための名前を送信します。スニペットの内容は送信しません。ライセンスキーは Mac の Keychain に保存します。
<!-- source: https://docs.lemonsqueezy.com/api/license-api/activate-license-key の activate のパラメータは license_key (The license key to activate.) と instance_name (A label for the new instance to identify it in Lemon Squeezy.) -->

**iOS 版**のライセンスはアプリ内購入で販売し、決済は Apple Inc. が処理します。提供者は決済情報を受け取りません。購入状況は端末の App Store の購入履歴で確認します。

### 更新の確認（Mac 版）

Mac 版は、更新の確認のため GitHub Pages（ https://bannzai.github.io/tanzaku/ ）に置いた更新情報を取得し、更新がある場合は GitHub Releases から新しい版をダウンロードします。この通信ではスニペットの内容を送信しません。GitHub Pages への通信の際、GitHub, Inc. は IP アドレスを記録し、GitHub のプライバシーステートメント（ https://docs.github.com/ja/site-policy/privacy-policies/github-general-privacy-statement ）に従って扱います。
<!-- source: https://docs.github.com/en/pages/getting-started-with-github-pages/about-github-pages 「When a GitHub Pages site is visited, the visitor's IP address is logged and stored for security purposes, regardless of whether the visitor has signed into GitHub or not.」 -->

### 提供者が収集する情報

本サービスはアカウント登録を必要とせず、提供者がスニペット等をサーバーで収集・保管することはありません。本サービスは広告・分析のための SDK を含みません。提供者が受け取る個人情報は、Mac 版の購入時に Lemon Squeezy から受け取る購入者の情報（上記「ライセンスの購入と確認」）と、ユーザーがメール等で問い合わせを行った場合の連絡先と問い合わせ内容だけです。

## 利用目的

利用者情報の具体的な利用目的は以下のとおりです。

- ライセンスの有効化・確認・購入状況の復元等、本サービスの提供、維持、保護および改善のため
- 本サービスに関するご案内、購入やライセンスに関するお問い合わせ等への対応のため
- 本サービスに関する提供者の規約、ポリシー等に違反する行為に対する対応のため
- 本サービスに関する規約等の変更などを通知するため

## 保存期間

- スニペット等は、ユーザーが本サービス内で削除するか本サービスを削除するまで端末内に、iCloud で同期している場合はユーザーが削除するまでユーザーの iCloud に保存されます
- Mac 版のライセンスキーは、ユーザーが本サービスでライセンスを解除するまで Mac の Keychain に保存されます
- Lemon Squeezy から受け取る購入者の情報は、ライセンスの提供、お問い合わせへの対応、法令上の義務の履行に必要な期間保存します。Lemon Squeezy が取得した情報は、Lemon Squeezy のプライバシーポリシーに定める期間保存されます
- 問い合わせの連絡先と内容は、対応の完了後、提供者が対応の記録として必要と判断する期間保存し、その後削除します

## 第三者提供

提供者は、利用者情報のうち、個人情報については、あらかじめユーザーの同意を得ないで、第三者（日本国外にある者を含みます。）に提供しません。ただし、次に掲げる必要があり第三者（日本国外にある者を含みます。）に提供する場合はこの限りではありません。

- 提供者が利用目的の達成に必要な範囲内において個人情報の取扱いの全部または一部を委託する場合
- 合併その他の事由による事業の承継に伴って個人情報が提供される場合
- 国の機関もしくは地方公共団体またはその委託を受けた者が法令の定める事務を遂行することに対して協力する必要がある場合であって、ユーザーの同意を得ることによって当該事務の遂行に支障を及ぼすおそれがある場合
- その他、個人情報の保護に関する法律（以下「個人情報保護法」といいます。）その他の法令で認められる場合

## 個人情報の開示・訂正・利用停止・消去

提供者は、ユーザーから、個人情報保護法の定めに基づき個人情報の開示・訂正・利用停止・消去を求められたときは、ユーザーご本人からのご請求であることを確認の上で、遅滞なく対応します（当該個人情報が存在しないときにはその旨を通知いたします。）。ただし、個人情報保護法その他の法令により提供者が義務を負わない場合は、この限りではありません。

端末内とユーザーの iCloud に保存されているスニペット等は提供者が保有していないため、ユーザー自身が次の手順で消去できます。

1. 本サービスでスニペットを削除する。iCloud で同期している場合、削除は同期している他の端末とユーザーの iCloud にも反映されます
2. すべてのデータを消去する場合は、すべてのスニペットを削除して同期が済んだ後、各端末から本サービスを削除する

## お問い合わせ窓口

ご意見、ご質問、苦情のお申出その他利用者情報の取扱いに関するお問い合わせは、以下の窓口までお願いいたします。

- 提供者: bannzai
- 連絡先: bannzai.app@gmail.com

## プライバシーポリシーの変更手続

提供者は、必要に応じて、本ポリシーを変更します。ただし、法令上ユーザーの同意が必要となるような本ポリシーの変更を行う場合、変更後の本ポリシーは、提供者所定の方法で変更に同意したユーザーに対してのみ適用されるものとします。なお、提供者は、本ポリシーを変更する場合には、変更後の本ポリシーの施行時期および内容をアプリ上での表示その他の適切な方法により周知し、またはユーザーに通知します。

制定日: 2026 年 9 月 28 日
