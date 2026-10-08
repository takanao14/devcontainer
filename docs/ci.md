# CI のビルド・検証・公開

## 構成

`.forgejo/workflows/image.yml` は Forgejo Actions の `ubuntu-24.04` runner を使用する。
main への push、pull request、手動実行でテストとイメージのビルド・検証を行う。
公開は main への push または main 上の手動実行に限り、検証成功後に実行する。

公開先は `forgejo.home.butaco.net/takanao/devcontainer-images`。
レジストリのホスト名は workflow の `CONTAINER_REGISTRY` に定義する。
共通イメージのタグは `ci-<commit>-<run>-<attempt>`、DNS 派生イメージは
`dns-ci-<commit>-<run>-<attempt>` で、既存タグへの上書きを前提としない。
CLI バージョンはイメージ内の `versions.txt` と検証ログ、公開先と digest は公開ログに残る。

## Runner と公開設定

runner のジョブ環境には Docker CLI、Make、Bash、jq、Mike Farah yq v4、Git、
checkout アクション用の Node.js が必要。Docker daemon へのアクセスと、
Ubuntu・npm・GitHub Releases・checkout アクションの取得先への通信も必要になる。

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
make smoke-remote
make check-dns-lock
make check-go-lock
make check-common-lock
make check-rust-lock
make build-dns
make verify-dns
make verify-dns-lock
```

- `test` はランチャーの設定検証を確認する。
- `check-dns-lock` は宣言とロックの対応、および AMD64 / ARM64 両方の URL・SHA-256 を確認する。
  Go/API の宣言・ロックも `check-go-lock` で同じ条件を確認する。
  共通ツールは `check-common-lock`、Rust のコンポーネント指定と Python 依存グラフの
  ファイル存在は `check-rust-lock` で確認する。Go/API と Rust のイメージビルド・実行検証は
  引き続きローカルで行う。
- DNS 派生イメージは同じ実行で検証した共通イメージからビルドする。
  `verify-dns` は非 root 実行、バージョン、ダミーの暗号化・復号、direnv を確認する。
  `verify-dns-lock` はロック欠落とチェックサム改変の拒否を確認するため、テスト用アーティファクトを取得する。
  両イメージの検証成功後に公開を開始する。公開途中の失敗では、先に公開したタグが残る場合がある。
- `verify` は非 root 実行、パスワードなし sudo の拒否、CLI のバージョン記録との一致を確認する。
- `smoke-daemon` は一時的な名前付きボリュームを使い、読み取り専用アクセス、
  コンテナ再作成後の状態保持、CLI の起動オプションを確認する。
  runner のジョブがコンテナ内で動作していても、Docker daemon とパスの共有を必要としない。
- `smoke-remote` は実コンテナ内のモック CLI を使用し、端末なしでの稼働継続と SIGTERM で
  リモート停止処理が呼ばれることを確認する。認証情報・通信・ホストのバインドマウントは使用しない。
  実際のペアリングやスマホの切断状態は検証しない。

ホストのバインドマウントとソース編集の反映は、ローカルの `make smoke` で別途確認する。
`smoke-daemon` の成功だけではホストのバインドマウントを検証したことにはならない。
どちらの結合テストも認証情報を使用せず、終了時にテスト用ボリュームを削除する。

## 検証状況

DNS 派生イメージの CI ジョブへの追加はローカルで検査済み。Forgejo 上での実行・公開は未確認。
mise 管理に移行した共通・Go/API・Rust/LED・DNS イメージの ARM64 ビルドと
ツール検証はローカルで実行済み。再ビルド時の CLI は Codex 0.161.0、Claude Code 2.1.293。
この共通イメージで daemon の状態保持とリモート終了処理も確認した。
ロックの更新は `make lock-dns` と差分レビューで行う。CI はコミット済みロックを検査し、
ロックの自動生成・更新はまだ行わない。

[CI 実行 #1](https://forgejo.home.butaco.net/takanao/devcontainer-images/actions/runs/1)で、
amd64 ビルド、ランチャー検証、権限・永続化テスト、レジストリへの公開が成功した。
公開タグは `ci-478ed3bb4bab3216faeaf698a96563f066bd68ac-533-1`。
CLI は Codex 0.160.1、Claude Code 2.1.292。Secret の利用も確認済み。

arm64 のローカルビルド、権限・マウント・状態保存のテスト、両 CLI のサインインと
再起動後の認証・履歴保持は、利用者の macOS / OrbStack 環境で確認済み。
CI は runner のネイティブアーキテクチャのみを公開し、複数アーキテクチャでの公開は未検証。
リモート終了処理のスモークテストと既存のマウント・状態保存テストは、
ローカル ARM64 イメージで実行済み。

[CI 実行 #3](https://forgejo.home.butaco.net/takanao/devcontainer-images/actions/runs/3)で、
共通ツール追加後の AMD64 ビルド、yq 4.54.1 の SHA-256 検証と YAML/JSON 変換、
ShellCheck 0.11.0、権限・永続化・リモート終了処理のテスト、レジストリ公開が成功した。
実行 #2 は runner に rg がないためテストで失敗し、テスト側の依存を修正して再実行した。
公開タグは `ci-06f212e6b135253e661c2acdc33101b68a1449a0-540-1`、
公開先は `forgejo.home.butaco.net/takanao/devcontainer-images`。
digest は `sha256:884afb83a0ea0004e13f373edebdc0d939e61a2ea6ae597d627028f4f864a9dc`。
これは AMD64 の成果物であり、ARM64 の CI ビルド・公開は引き続き未対応。

手元の OrbStack からの公開イメージ取得は、レジストリへの HTTPS 接続で `EOF` となり未完了。
ホスト側の HTTPS 接続は認証要求（401）を返すため、Docker daemon 側の接続経路の調査が必要。
