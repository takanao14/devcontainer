# プロジェクト別ツール一覧

2026-10-07 にローカルのプロジェクト設定を確認した。以下のバージョンは
リポジトリの要件または固定値であり、最新版かどうかを独立に検証したものではない。

## 共通ベース

Ubuntu、Bash、Git（サブモジュールを含む）、CA 証明書、curl、wget、
GCC/G++、Make（`build-essential`）、OpenSSH クライアント、jq、Mike Farah yq v4、ShellCheck、ripgrep、rsync、
tar、zip/unzip、sudo、基本的なプロセス・ネットワークユーティリティ。
これらは Dockerfile で提供している。エージェント実行用に Codex CLI、Claude Code、
Node.js と npm も共通イメージに含む。
yq は 4.54.1 に固定し、AMD64 / ARM64 の配布バイナリーを公開 SHA-256 で検証する。
ShellCheck は Ubuntu のパッケージを使用する。
Ubuntu の Node.js / npm パッケージの依存関係には Python 3 が含まれる。
Python のプロジェクト用ライブラリや Ansible は共通イメージの提供対象には含めない。

## プロジェクト固有のツール

| プロジェクト | 開発・ビルド用ツール | 追加の運用・実行時要件 | 確認元 |
| --- | --- | --- | --- |
| homelab | Terraform、Terragrunt、Packer（>=1.15.0）、Python >=3.12、ansible-core、ansible-lint、必要な Ansible コレクション、Helm、Helmfile、helm-diff、kubectl、k0sctl、Cilium CLI、ShellCheck | SOPS、age、direnv、Mike Farah yq v4、jq、イメージの準備・アップロード用の QEMU ツール（`qemu-img`）・xz・rclone、秘密情報管理用の OpenBao CLI（`bao`） | `README.md`、`tf/README.md`、`packer/README.md`、`k0s/README.md`、`ansible/requirements.yaml`、`.github/workflows/`、`scripts/install/vendor/` |
| homelab-private | dnscontrol（ワークフローでは 4.46.0 に固定）、Make | 暗号化環境の読み込み用の SOPS・age・direnv、DNS 確認用の curl・jq | `dns-record/Makefile`、`dns-record/.envrc`、`README.md`、`.forgejo/workflows/dns.yml` |
| dhcp-lease-observer | Go（go.mod では 1.26.0）、Make、競合検出テスト用の C コンパイラー | 手動診断用の SSH クライアント。アプリケーションの SSH 通信は Go ライブラリで提供 | `go.mod`、`Makefile`、`.github/workflows/release.yaml` |
| led-service2 | rustup 経由の Rust、Cargo、rustfmt、Clippy、protoc（`protobuf-compiler`）、pkg-config、GCC/G++、ALSA ヘッダー（`libasound2-dev`）、Python 3 | デプロイと検証用の ansible-core・ansible-lint・pipx、ソースのデプロイ用の SSH クライアント・rsync | `Cargo.toml`、`build.rs`、`README.md`、`Makefile`、`deploy.sh`、`.github/workflows/ci.yml` |
| slack-bot | Go（go.mod では 1.26.0）、Make、競合検出テスト用の C コンパイラー | コンテナビルド用の Docker CLI/Buildx と Docker デーモンへのアクセス、ローカル実行用の日本語 TTF フォント | `go.mod`、`Makefile`、`Dockerfile`、`README.md` |
| led-image-api | Go（go.mod では 1.26）、Buf CLI、Make、Git、diff | Buf のリモートコード生成プラグインへのネットワークアクセス | `go.mod`、`Makefile`、`buf.gen.yaml`、`README.md` |

## バージョンと環境の詳細

- homelab は、dotfiles から取り込んだ mise 設定とロックファイルで共通 Linux CLI の
  バージョンを管理している（ADR-0049）。確認時点の設定では Terragrunt 1.1.6、
  Helm 4.3.0、Helmfile 1.8.1、k0sctl 0.33.1、Cilium CLI 0.20.1、
  ansible-core 2.21.4、ansible-lint 26.9.0、SOPS 3.13.3、age 1.3.2、
  direnv 2.37.1、yq 4.54.1、uv 0.12.22 に固定している。インストーラーは
  helm-diff 3.15.15 に固定し、Ansible コントローラーには Python >=3.12 を要求する。
  インフラ用レイヤーの設計では、これらの管理済みバージョンを再利用する。
- homelab の Terraform 文書と CI は `terraform` を使用する。一方、共通 mise 設定には
  OpenTofu 1.13.1 も含まれる。OpenTofu は追加の選択肢であり、
  リポジトリの互換性を確認せずに Terraform を置き換えない。
- homelab の Ansible コレクションは
  `ansible-galaxy collection install -r ansible/requirements.yaml` でインストールする。
  対象は community.general 13.4.0、community.sops 2.4.0、
  community.postgresql 5.0.0、ansible.posix 2.2.2。
- homelab は任意の管理ツールとして Argo CD CLI、k9s、krew、kubie、kdash、
  promtool（Prometheus 由来）、AWS CLI、GitHub CLI も宣言している。
  actionlint はワークフローの検証に使用する。これらはインフラの編集・検証に必要な
  最小構成とは分けて扱う。対象ホストに配置されるサービスは開発コンテナの依存関係ではない。
- Go: `dhcp-lease-observer` のリリース CI は `1.27.x`、`slack-bot` の Dockerfile は
  `golang:1.27.1` を使用する。共通 Go レイヤーでは 1.26 の宣言との整合を確認する。
  go.mod だけからツールチェーンを決めない。
- Rust: `led-service2` の CI は stable を選択しており、確認したビルド設定には
  固定の Rust バージョンがない。ビルド前に `led-image-api` サブモジュールを初期化する。
- Linux エミュレーター: minifb は X11/Wayland の開発ライブラリやディスプレイ接続も
  必要とする可能性がある。これはエミュレーターの依存関係から推測した追加要件であり、
  リポジトリの CI で検証済みのパッケージ一覧ではない。Linux CI は Raspberry Pi 機能を検証する。
- `led-service2` の `make build` は、すべての Linux ホストで Raspberry Pi 機能を選択する。
  devcontainer でエミュレーターを検証する場合は、必要なグラフィックライブラリを用意し、
  `cargo test --locked --no-default-features --features emulator` を明示的に実行する。
  LED・音声の実動作にはハードウェアとデバイスへのアクセスが必要であり、
  ビルドツールのインストールだけでは提供されない。
- Python 3 は Rust 依存パッケージの経過期間チェックと Ansible の単体テストに使用する。
  pipx で ansible-core と ansible-lint を分離してインストールできる。
- `slack-bot` は本番イメージに BIZ UDPGothic v1.051 を同梱している。
  ローカル実行では日本語 TTF を用意し、`SLACK_BOT_FONT_PATH` を設定する。
  本番用 Dockerfile はフォントアーカイブとライセンスの両方を SHA-256 で検証する。
- Buf は固定バージョンのリモートプラグイン（`protocolbuffers/go:v1.36.11`、
  `grpc/go:v1.6.1`）を使用する。現在の Buf 設定では、ローカルの
  `protoc-gen-go` と `protoc-gen-go-grpc` バイナリーは不要。Rust ビルドは別途 protoc を必要とする。
- Node.js と Renovate は `homelab-private` のバージョン固定済み Renovate 診断コンテナ内で
  使用する。通常の dnscontrol 開発には Node.js は不要。
- systemd は observer と LED サービスのデプロイ先の要件であり、
  この開発イメージの要件ではない。

## レイヤー設計への適用

用途別イメージの構成は[実装計画](devcontainer-implementation-plan.md#8-プロジェクト別イメージ)を参照。
選定上の制約は次のとおり。

- Go と dnscontrol はプロジェクト間でバージョンが異なるため、共通バージョンの採用には
  互換性の検証が必要。homelab の mise は dnscontrol v5.3.0、
  homelab-private の DNS ワークフローは 4.46.0 に固定している。
- Rust/LED の依存関係には Python 3、pipx、ALSA ヘッダーも含まれる。
  エミュレーター用のグラフィックライブラリは別途必要となる可能性がある。
- インフラ用ツールのバージョン参照元は homelab の取り込み済み mise 設定・ロックファイル。
  DNS レイヤーと共通するツールも含む。
- Docker CLI/Buildx はイメージをビルドする用途に必要。Docker デーモンへのアクセスや
  グラフィック・音声の転送はツールのインストールとは別の実行環境要件。

秘密情報、SSH 秘密鍵、age 秘密鍵の供給場所は実行環境とし、イメージには含めない。
