# CI とローカル検証

## 責務

`.forgejo/workflows/image.yml` は main の push、pull request、手動実行で
`make check` を実行する。イメージの生成・公開、コンテナ起動、ロック再生成は含まない。
runner のラベルは `ubuntu-24.04`。Bash、Make、Git、jq、Mike Farah yq v4、
ShellCheck、Node.js と npm が必要で、Docker daemon とレジストリ認証は不要。

`check` はランチャーとリモート操作のモックテスト、候補更新の失敗処理、
mise ブートストラップのバージョン・チェックサム・実行時検証値の一致、
共通・Go・Rust・インフラの宣言と保存済みロックの整合性、シェル構文・ShellCheck、
npm の48時間の選択期限を確認する。workflow の YAML と埋め込まれたシェルも検査する。
保存済みロックの検査には Linux x64 / ARM64 の URL・チェックサムと
Python 依存グラフのファイル存在が含まれる。配布物の取得・インストール成功は保証しない。

## 利用端末での検証

```sh
make check
make update-local KIND=common UPDATE_MODE=rebuild
# 必要な派生イメージだけを選択する:
make update-local KIND=go
make update-local KIND=rust
make update-local KIND=infra
```

`update-local` は一意の候補参照を作成し、共通の `verify-local` が成功した後、
選択した派生イメージをビルド・検証する。
`verify-local` は CLI・ツール・非 root・sudo 制限、ホストの bind mount とソース編集、
一時ボリュームの状態保持、モック CLI によるリモート停止を確認する。
実際の認証・スマホからの接続・ペアリング再利用は利用者による確認が必要。
テストは既存の認証情報を使用せず、テスト用ボリュームを終了時に削除する。

インフラの DNS 機能は `verify-infra` と `verify-infra-lock` でツール、ダミー暗号化・復号、
ロック不足とチェックサム改変の拒否を確認する。Go は `verify-go` で
ツールと暗黙のツールチェーン取得の無効化を確認する。
Rust は `verify-rust` と `verify-rust-lock` でコンポーネント・ネイティブライブラリ・
Ansible と Python 依存グラフの改変拒否を確認する。
DNS の改変拒否テストはテスト用配布物の取得を必要とする。

インフラは `verify-infra` で7ツールのバージョン・権限・固定パスと、
ダミー構成のオフライン検査を行う。`check-infra-project` は homelab の整形と
Packer の構文のみを確認し、provider・プラグインの設定検証やデプロイを含めない。

候補の参照、イメージ ID、バージョン、検証結果は `.local-builds/` に記録する。
失敗した候補と利用中のイメージは別の参照であり、更新コマンドによる切り替え・
環境停止・状態削除は行わない。利用と復帰の手順は README に記載する。
未検証のアーキテクチャは、その端末で利用前に検証する。

## 依存更新

Renovate は既存の `takanao/renovate` が実行し、このリポジトリへの Write 権限を必要とする。
更新候補には2日の待機期間を適用し、公開日時不明の候補は採用しない。
Dependency Dashboard の承認後に PR を作成し、自動マージは無効。
生成物 `images/rust/tools/.mise/locks/**` は検出対象外とする。

ブートストラップの更新では配布チェックサムと検証の固定値を揃える。
用途別宣言の更新では `make update-locks` を利用端末で実行し、ロック・依存 sidecar の
差分をレビューする。`make check-locks` は専用コンテナで4用途の両 Linux プラットフォームの
ロックを再生成し、差分を検査する。これらはイメージを生成するローカル専用操作で、
CI の `check` とは異なる。反映にはホストの rsync が必要。
マージ前には対象イメージのローカルビルド・検証結果を PR に記録する。

既存 Renovate の GitHub fine-grained token による依存取得は確認済み。
同 runner は IPv6 のインターネット経路を持たないため、手動・定期実行に
`--dns-result-order=ipv4first --no-network-family-autoselection` を使用する。
このリポジトリの CI 簡素化は Renovate の実行設定を変更しない。

## 旧 CI からの整理

PR #11 の per-run イメージ削除は、イメージを生成しない workflow では使用しない。
専用 cleanup と GC 設定例は本変更で削除する。共有 runner の Docker 設定には触れない。

以前の AMD64 CI では共通・DNS・Go・Rust のビルド・検証・公開が成功した。
新しい CI ではその実行時検証を行わない。ローカル運用の確認後に管理者が次を行う。

1. このリポジトリ専用の Actions Secret `REGISTRY_USER` と `REGISTRY_PASSWORD` を削除する。
2. 共有トークンの失効は他用途の有無を確認して判断する。
3. 既存の runner イメージ・キャッシュとレジストリ成果物は、他ジョブ・利用端末の参照を確認して整理する。

通常のビルドや CI には全体 prune を含めない。
移行の詳細と完了条件は[ローカルビルド計画](local-build-plan.md)を参照する。

## 本変更の検証

2026-10-10 にローカル ARM64 で `make check`、共通候補の `update-local`、
その候補をベースとした DNS・Go・Rust のビルドと各検証を確認した。
バックアップ・復元手順は一時ボリュームのダミーデータで所有者とアクセス権の保持を確認した。
実際の認証状態のバックアップからの復元は未確認。

2026-10-11 にインフラ候補の ARM64 `update-local`、`make check`、Renovate 設定検証と、
homelab の `check-infra-project` を確認した。AMD64 の実ビルドは未確認。

DNS 統合後も ARM64 の `update-local KIND=infra`、ロック再生成の配布情報一致、
ロック破損拒否、両プロジェクトのオフライン検査と Renovate 設定検証を確認した。
PR #16 マージ後の `38135279e8fd` から統合イメージをビルドし、両プロジェクトの
オフライン検査を再確認した。homelab のリモートコンテナを停止し、Codex・Claude の
状態ボリュームをバックアップした後、同じボリュームで統合イメージに切り替えた。
コンテナの `running` を確認し、既存ペアリングによるスマホからの再接続は利用者が確認した。
Claude の実接続、履歴の内容、バックアップからの復元は今回の確認に含めていない。
