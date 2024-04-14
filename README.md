## このリポジトリは？

AWS環境を構築するterraform。

S3に格納した静的コンテンツをCloudfrontでホスティングする。

さらに、WAFを使用して送信元のIPアドレスを限定する。

## hugoとの連携

GitHubActionsを使用し、hugoで作成したファイルをこのs3に格納する。