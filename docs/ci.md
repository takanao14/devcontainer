# CI のビルド・検証・公開

## 構成

`.forgejo/workflows/image.yml` は Forgejo Actions の `ubuntu-24.04` runner を使用する。
main への push、pull request、手動実行でテストとイメージのビルド・検証を行う。
公開は main への push または main 上の手動実行に限り、検証成功後に実行する。

公開先は `forgejo.home.butaco.net/takanao/devcontainer-images`。
レジストリのホスト名は workflow の `CONTAINER_REGISTRY` に定義する。
タグは `ci-<commit>-<run>-<attempt>` で、既存タグへの上書きを前提としない。
CLI バージョンはイメージ内の `versions.txt` と検証ログ、公開先と digest は公開ログに残る。

## Runner と公開設定

runner のジョブ環境には Docker CLI、Make、Bash、jq、Mike Farah yq v4、Git、
checkout アクション用の Node.js が必要。Docker daemon へのアクセスと、
Ubuntu・npm・checkout アクションの取得先への通信も必要になる。

リポジトリの Actions 設定には次を登録する。

| 種類 | 名前 | 内容 |
| --- | --- | --- |
| Secret | `REGISTRY_USER` | パッケージの公開権限を持つユーザー |
| Secret | `REGISTRY_PASSWORD` | 同ユーザーのパッケージ書き込み用トークン |

公開処理は workflow 内で実行する。認証情報は標準入力で Docker に渡し、
Docker の認証設定はジョブ専用の一時ディレクトリに保存する。処理終了時にそのディレクトリを削除する。
認証やタグ付けが失敗した場合、後続の公開処理は実行しない。

## 検証

```sh
make test
make verify
make smoke-daemon
```

- `test` はランチャーの設定検証を確認する。
- `verify` は非 root 実行、パスワードなし sudo の拒否、CLI のバージョン記録との一致を確認する。
- `smoke-daemon` は一時的な名前付きボリュームを使い、読み取り専用アクセス、
  コンテナ再作成後の状態保持、CLI の起動オプションを確認する。
  runner のジョブがコンテナ内で動作していても、Docker daemon とパスの共有を必要としない。

ホストのバインドマウントとソース編集の反映は、ローカルの `make smoke` で別途確認する。
`smoke-daemon` の成功だけではホストのバインドマウントを検証したことにはならない。
どちらの結合テストも認証情報を使用せず、終了時にテスト用ボリュームを削除する。

## 検証状況

[CI 実行 #1](https://forgejo.home.butaco.net/takanao/devcontainer-images/actions/runs/1)で、
amd64 ビルド、ランチャー検証、権限・永続化テスト、レジストリへの公開が成功した。
公開タグは `ci-478ed3bb4bab3216faeaf698a96563f066bd68ac-533-1`。
CLI は Codex 0.160.1、Claude Code 2.1.292。Secret の利用も確認済み。

arm64 のローカルビルドは検証済みだが、CI は runner のネイティブアーキテクチャのみを公開する。
実際の CLI サインインと複数アーキテクチャでの公開は未検証。

手元の OrbStack からの公開イメージ取得は、レジストリへの HTTPS 接続で `EOF` となり未完了。
ホスト側の HTTPS 接続は認証要求（401）を返すため、Docker daemon 側の接続経路の調査が必要。
