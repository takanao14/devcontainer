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
固定した mise 2026.10.4 と `tools/common` の設定・ロックで導入する。
派生イメージは共通イメージの mise を使用する。
ShellCheck は Ubuntu のパッケージを使用する。
Ubuntu の Node.js / npm パッケージの依存関係には Python 3 が含まれる。
Python のプロジェクト用ライブラリや Ansible は共通イメージの提供対象には含めない。

## プロジェクト固有のツール

| プロジェクト | 開発・ビルド用ツール | 追加の運用・実行時要件 | 確認元 |
| --- | --- | --- | --- |
| homelab | Terraform、Terragrunt、Packer（>=1.15.0）、Python >=3.12、ansible-core、ansible-lint、必要な Ansible コレクション、Helm、Helmfile、helm-diff、kubectl、k0sctl、Cilium CLI、ShellCheck | SOPS、age、direnv、Mike Farah yq v4、jq、イメージの準備・アップロード用の QEMU ツール（`qemu-img`）・xz・rclone、秘密情報管理用の OpenBao CLI（`bao`） | `README.md`、`tf/README.md`、`packer/README.md`、`k0s/README.md`、`ansible/requirements.yaml`、`.github/workflows/`、`scripts/install/vendor/` |
| homelab-private | dnscontrol（ワークフローでは 5.3.0 に固定）、Make | 暗号化環境の読み込み用の SOPS・age・direnv、DNS 確認用の curl・jq | `dns-record/Makefile`、`dns-record/.envrc`、`README.md`、`.forgejo/workflows/dns.yml` |
| dhcp-lease-observer | Go（go.mod では 1.26.0）、Make、競合検出テスト用の C コンパイラー | 手動診断用の SSH クライアント。アプリケーションの SSH 通信は Go ライブラリで提供 | `go.mod`、`Makefile`、`.github/workflows/release.yaml` |
| led-service2 | rustup 経由の Rust、Cargo、rustfmt、Clippy、protoc（`protobuf-compiler`）、pkg-config、GCC/G++、ALSA ヘッダー（`libasound2-dev`）、Python 3 | デプロイと検証用の ansible-core・ansible-lint・pipx、ソースのデプロイ用の SSH クライアント・rsync | `Cargo.toml`、`build.rs`、`README.md`、`Makefile`、`deploy.sh`、`.github/workflows/ci.yml` |
| slack-bot | Go（go.mod では 1.26.0）、Make、競合検出テスト用の C コンパイラー | コンテナビルド用の Docker CLI/Buildx と Docker デーモンへのアクセス、ローカル実行用の日本語 TTF フォント | `go.mod`、`Makefile`、`Dockerfile`、`README.md` |
| led-image-api | Go（go.mod では 1.26）、Buf CLI、Make、Git、diff | Buf のリモートコード生成プラグインへのネットワークアクセス | `go.mod`、`Makefile`、`buf.gen.yaml`、`README.md` |

## バージョンと環境の詳細

- 最初の派生イメージは `images/go/Dockerfile` とし、Go 1.27.1 と Buf 1.73.0 を提供する。
  AMD64 / ARM64 の公式アーカイブを SHA-256 で検証し、`GOTOOLCHAIN=local` とする。
  mise 2026.10.4 と `images/go/tools` の設定・ロックを使用する。
  実行時はイメージ所有の固定パスを使用し、プロジェクトの mise 設定では切り替えない。
  ローカル ARM64 で `dhcp-lease-observer`（`92ab867`）の通常テスト・競合検出テスト・
  `go vet`・ビルドを確認した。依存取得後はネットワークなしで、読み取り専用の
  ホストソースをコンテナ内にコピーして検証する。
  `led-image-api`（`e7099d5`）では Buf のフォーマット・lint・リモート生成結果の一致と、
  Go のビルド・`go vet` を確認した。Go テストの実行対象にはテストファイルがない。
  mise 管理への移行後も、両プロジェクトの同じ検証をローカル ARM64 で確認した。
  リモート生成は bridge、それ以降の Go 検証はネットワークなしで実行する。
  派生イメージのビルド・実行時検証は利用端末で行う。
  Go/API の両アーキテクチャ向けロック検査は Forgejo workflow に含む。

- Rust/LED イメージは `images/rust/Dockerfile` で Rust 1.99.0、rustfmt、Clippy、
  protoc、ALSA・X11/Wayland の開発ライブラリ、Python、uv 0.12.23、ansible-core 2.21.5、
  ansible-lint 26.9.0 を提供する。rustup 1.29.1 のインストーラーは公式 SHA-256 で検証し、
  mise 2026.10.4 と `images/rust/tools` の設定で Rust のバージョン・プロファイル・
  コンポーネントを指定する。Ansible の推移的依存は uv.lock のハッシュ付きグラフを使用し、
  ansible-lint の環境も ansible-core 2.21.5 を使用する。ツールチェーンはイメージ所有で、
  Cargo キャッシュは非 root ユーザーが書き込める。実行時の自動インストールと
  rustup の自動更新は無効。2026-10-08 にローカル ARM64 で `led-service2`（`90d087e`）の
  エミュレーター構成のフォーマット・Clippy・ビルド・Rust テスト32件、Python テスト8件、
  Ansible lint を確認した。依存取得後の検証はネットワークなしで実行した。
  mise・uv 管理への移行後も同じ検証と、依存グラフのハッシュ改変拒否を確認した。
  Raspberry Pi 構成のビルド、画面・音声・LED の実動作は未確認。
  インフラ用イメージは未実装。
  uv のロックは GitHub の attestation 検証付きで生成し、チェックサムは公式の .sha256 と一致する。
  導入時はその SHA-256 を検証する。

- DNS イメージは `images/dns/Dockerfile` で dnscontrol 5.3.1、SOPS 3.13.3、
  age 1.3.2、direnv 2.38.1 を提供する。mise 2026.10.4 と用途別の設定・ロックで導入し、
  各配布物は公式 SHA-256 で検証する。取り込み元は `images/dns/tools/SOURCE` に記録する。
  SOPS は Aqua バックエンドを使用する。mise 2026.10.0 はチェックサム付きロックの
  来歴情報を信頼し、導入時の SLSA 再検証は行わない。署名者情報の欠落は解消していない。
  2026-10-08 にローカル ARM64 で `homelab-private`（`adf7ac2`）の `make check` を
  秘密情報なし・ネットワークなしで確認した。SOPS/age は一時鍵とダミーデータで
  暗号化・復号を確認し、direnv もダミー環境変数で確認した。
  ロック不足・不正チェックサムの拒否、プロジェクト設定による暗黙の切り替えがないことも
  確認した。実際の秘密情報の供給・復号と DNS preview/push は検証対象に含めていない。
  Forgejo workflow は保存済みロックの整合性検査を行い、ビルド・公開は行わない。
  旧 Forgejo CI の実行 #4 では AMD64 のビルド・検証・公開を確認した。

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
- Linux エミュレーター: minifb のビルド用に X11/Wayland の開発ライブラリを備える。
  画面表示には別途ディスプレイ接続が必要。プロジェクトの Linux CI は Raspberry Pi
  機能を検証しており、エミュレーターの CI は macOS を使用する。
- `led-service2` の `make build` は、すべての Linux ホストで Raspberry Pi 機能を選択する。
  devcontainer でエミュレーターを検証する場合は、必要なグラフィックライブラリを用意し、
  `cargo test --locked --no-default-features --features emulator` を明示的に実行する。
  LED・音声の実動作にはハードウェアとデバイスへのアクセスが必要であり、
  ビルドツールのインストールだけでは提供されない。
- Python 3 は Rust 依存パッケージの経過期間チェックと Ansible の単体テストに使用する。
  Rust/LED イメージでは ansible-core と ansible-lint を uv の分離した環境に導入する。
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

- Go の共通バージョンの採用にはプロジェクトごとの互換性検証が必要。
  dnscontrol は homelab の mise と homelab-private の DNS ワークフローともに 5.3.0。
- Rust/LED の依存関係には Python 3、pipx、ALSA ヘッダーも含まれる。
  エミュレーター用のグラフィックライブラリは別途必要となる可能性がある。
- インフラ用ツールのバージョン参照元は homelab の取り込み済み mise 設定・ロックファイル。
  DNS レイヤーと共通するツールも含む。
- Docker CLI/Buildx はイメージをビルドする用途に必要。Docker デーモンへのアクセスや
  グラフィック・音声の転送はツールのインストールとは別の実行環境要件。

秘密情報、SSH 秘密鍵、age 秘密鍵の供給場所は実行環境とし、イメージには含めない。
