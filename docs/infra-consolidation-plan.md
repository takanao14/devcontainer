# DNS・インフライメージの統合計画

## 目的と構成

管理対象のイメージは共通・Go/API・Rust/LED・インフラの4種類とする。
インフライメージは共通イメージを直接ベースとし、DNS とインフラのツールを備える。
Dockerfile、ツール宣言、ロック、更新候補は用途ごとに重複しない構成とする。

| 項目 | 統合後の状態 |
| --- | --- |
| ビルド定義 | `images/infra/Dockerfile` |
| ツール管理 | `images/infra/tools/config.toml`、`mise.lock`、`SOURCE` |
| DNS ツール | DNSControl 5.3.1、SOPS 3.13.3、age 1.3.2、direnv 2.38.1 |
| インフラツール | Terraform 1.16.5、Terragrunt 1.1.6、Packer 1.16.1 |
| 更新の入口 | `make update-local KIND=infra` |
| イメージ参照 | `INFRA_IMAGE_REF`。起動時は従来どおり `IMAGE_REF` |
| プロジェクト検査 | `check-dns-project` と `check-infra-project` が同じイメージを使用 |

統合の対象はイメージであり、実行するコンテナと状態はプロジェクトごとに分離する。
homelab と homelab-private はそれぞれ明示したソースだけをマウントし、認証・履歴・
ペアリングのボリューム識別は既存のプロジェクトパスに基づく。
ツールの追加だけではホストの認証情報やインフラ操作権限を付与しない。

## バージョンと検証の設計

7ツールの固定値、Linux x64 / ARM64 の配布 URL・チェックサム、取り込み元は
レビュー済みの入力とする。統合だけを理由とするバージョン更新は含めない。
新規バージョンの48時間待機、`mise install --locked`、root 所有の導入先、
作業ディレクトリに依存しない PATH、非 root 実行は既存方針に従う。
Terraform・Packer の更新確認は無効とする。

イメージ内の宣言の正本は `infra-tools` とする。バージョン記録は検査範囲を示す
`dns-versions.txt` と `infra-versions.txt` を保持し、ローカル更新記録には両方を含める。
DNS・インフラの検査スクリプトは用途別に保ち、統合イメージの検証で両方を実行する。
ロック不足・チェックサム改変の拒否も統合イメージの必須検証とする。

## 実装手順

1. DNS の宣言とロックの各ツールエントリーを `images/infra/tools` にまとめる。
   `SOURCE` に両方の参照元を残し、配布 URL・チェックサムが移動前と一致することを確認する。
   宣言の整合性検査と、専用コンテナによるロック再生成の差分確認を行う。
2. インフラの Dockerfile に DNS の導入・固定パス・バージョン記録を組み込む。
   DNS イメージを中間ベースとして保持せず、7ツールを同じ locked インストールで導入する。
3. Make と `scripts/local-update.sh` の入口を統一する。`verify-infra` は共通・DNS・
   インフラの実行検査を行い、`verify-infra-lock` はロック破損拒否を検査する。
   `update-local KIND=infra` はこれらがすべて成功した候補だけを検証済みとして記録する。
   `check-dns-project` と DNS 検査スクリプトを `INFRA_IMAGE_REF`・`infra-tools` に対応させる。
4. 独立した DNS の Dockerfile・ツール管理、`DNS_IMAGE_REF`、`KIND=dns`、
   `build-dns`・`lock-dns`・`verify-dns`・`verify-dns-lock`・`check-dns-lock` を整理する。
   旧入口の互換エイリアスは設けず、利用手順を統合後の入口に統一する。
   `check-infra-lock`、ロック生成の対象一覧、Renovate、静的 CI のモックテストを更新する。
5. README、ツール一覧、CI 文書を実装に合わせる。DNS のプロジェクト検査は残し、
   イメージのビルド・更新手順はインフラの節にまとめる。
   ツール一覧の「インフラ用イメージは未実装」という古い記述も訂正する。
6. ローカルで統合候補をビルド・検証する。homelab と homelab-private の検査後、
   利用者が選択したプロジェクトのコンテナを停止・バックアップし、新参照で再作成する。
   認証と既存ペアリングの再利用を確認する。

## 検証と完了条件

- `make check` と Renovate 設定検証が成功し、静的 CI は Docker を必要としない。
- Make のドライランとローカル更新のテストで、インフラ候補が指定した共通参照を使い、
  DNS 用の別イメージを生成しないことを確認する。
- ARM64 の実ビルドで7ツールのバージョン、固定パス、非 root・sudo 制限、
  設定・導入先の書き込み制限、ダミー暗号化・復号、ロック破損拒否が成功する。
- `check-dns-project` は homelab-private の `make check`、`check-infra-project` は
  homelab の整形と Packer の構文検査を、読み取り専用ソースの一時コピーで実行する。
  DNS 更新、Terraform apply、Packer build、実環境・ハードウェアへの操作は含めない。
- Linux x64 / ARM64 のロックを検査する。AMD64 の実ビルドを行わない場合は未検証と記録する。
- 再作成後もプロジェクトのソース・認証・ペアリング状態が保持されることを確認する。
  利用者の実確認とモック検査は分けて記録する。

## 切り替えと復帰

ビルドは実行中のコンテナを停止せず、旧イメージと状態ボリュームを削除しない。
旧 DNS・インフラの検証済み参照は復帰用として保持する。
問題があれば旧参照で再作成し、必要に応じて切り替え前の状態バックアップを復元する。
旧候補イメージの削除や保持世代の自動管理は別作業とする。
