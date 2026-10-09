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
CLI の取得期限はビルド時点の48時間前で、イメージ内の `npm-before.txt` に記録する。
`verify` は npm の選択処理で、期限直前・期限ちょうど・期限後のバージョンと
若い固定バージョンの拒否をオフラインで確認する。

`renovate.json` は `minimumReleaseAge: "2 days"` と厳密な候補フィルターを指定する。
公開日時がない候補は待機対象とする。用途別 mise 設定と固定した mise/rustup のバージョンを
検出するが、ブートストラップのチェックサム・検証用の固定値や用途別ロックの更新はレビューを必要とする。
実行基盤は既存の `takanao/renovate` を使用する。対象追加の
[PR #8](https://forgejo.home.butaco.net/takanao/renovate/pulls/8) はマージ済み。
対象は同リポジトリの
`config.js` の `repositories` に登録する。更新 PR は Dependency Dashboard の
承認後に作成し、自動マージは無効とする。Bot にはこのリポジトリの Write 権限が必要。
Bot の Dashboard 作成を確認済み。既存 workflow へ GitHub の fine-grained token を
Actions Secret 経由で渡した実行後、トークン不足・API レート制限の警告は解消した。
`images/rust/tools/.mise/locks/**` は生成物のため依存検出から除外し、更新対象を
用途別 `config.toml` に集約する。checkout のタグ検索警告は残っており、Renovate runner
からの配布元 API への通信と取得ログによる切り分けが必要。

`make check-locks` は固定した mise と uv を使い、4用途の Linux x64 / ARM64 ロックを
一時コンテナ内で再生成して差分を検査する。宣言したバージョンは変更しない。
CI の生成結果に差分があればイメージ公開前に失敗する。
`make update-locks` は同じ生成処理の結果を作業ツリーへ戻すため、差分をレビューしてコミットする。
Python の依存グラフは既存ロックを再利用し、依存の再解決による時刻だけの差分を作らない。
Renovate がロックを更新できない候補も、この手順でロック・チェックサム・検証の固定値を
揃えてからマージする。ロック生成用 Python は専用イメージに含み、ホストには要求しない。
Docker とのファイル受け渡しは `docker cp` を使用し、runner と daemon のパス共有は不要。
作業ツリーへ反映するホストには rsync が必要。

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

[CI 実行 #4](https://forgejo.home.butaco.net/takanao/devcontainer-images/actions/runs/4)で、
コミット `dabb144` の共通・DNS イメージの AMD64 ビルド、権限・48時間の取得期限・
daemon 状態保持・リモート終了処理の検証、DNS のダミー暗号化・復号とロック欠落／
チェックサム改変の拒否、レジストリ公開が成功した。
共通タグは `ci-dabb144bf7c5584c3d3c8cd6180f4bdaf5d5f779-551-1`、
DNS タグは同じタグに `dns-` を付ける。
公開先は `forgejo.home.butaco.net/takanao/devcontainer-images`。
共通 digest は `sha256:6870982fbc5ea017558cd3feb451d5d25220c68967edaedb86c1b33aa54f79d9`、
DNS digest は `sha256:5631a563b7576b349979a87f66611e67e3ba840d93317dca139e60e1f91f32dd`。
CLI は Codex 0.160.1、Claude Code 2.1.292。

mise 管理に移行した共通・Go/API・Rust/LED・DNS イメージの ARM64 ビルドと
ツール検証はローカルで実行済み。48時間の取得期限を適用した CLI は
Codex 0.160.1、Claude Code 2.1.291 で、npm の公開日時が期限内であることを確認した。
この共通イメージで daemon の状態保持とリモート終了処理も確認した。
Renovate 設定は公式イメージ `renovate/renovate:44.139.0` の厳密な設定検査に成功した。
用途別の既存 `lock-*` ターゲットも利用できる。CI は宣言・ロックの検査に加え、
`make check-locks` でロックの再生成・差分検査を行う。
ローカル ARM64 で再生成の差分検出、`update-locks` による正規化、再実行時の差分なしを
確認した。ステージ分割後の共通イメージのビルド・検証も成功した。
[CI 実行 #5](https://forgejo.home.butaco.net/takanao/devcontainer-images/actions/runs/5) で、
コミット `a89ac4e` の AMD64 runner における4用途の両 Linux プラットフォームの
ロック再生成・差分なし、共通・DNS イメージのビルド・検証・公開を確認した。
公開タグは `ci-a89ac4ecc856bf61f60598e2b8ca6a675e97cb39-552-1` とその `dns-` 接頭辞付き。
共通 digest は `sha256:24211521b2dd3f32d35c69aed6e793ca0889382c9a275f8a446c3b6d5da111a8`、
DNS digest は `sha256:18b2c43bf31d80e5809264b78483d3ab26881131c6b3ae9e0c6196ae36051b54`。

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
