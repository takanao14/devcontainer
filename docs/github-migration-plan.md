# GitHub への移行計画

## 目的と決定事項

通常の開発・PR・静的 CI・依存更新の正本は GitHub とする。
イメージのビルドと世代管理は利用端末の責務とし、GitHub のレジストリ・
イメージ公開ジョブ・専用 runner は通常運用の構成に含めない。

移行先は公開リポジトリ `takanao14/devcontainer` とする。
Renovate は他の GitHub リポジトリと同じホスト型 Renovate App を使用する。
dotfiles と homelab は2日待機と依存ごとのマージ方針を持つ。
本リポジトリのツール更新はロック生成とローカルビルド検証を必要とするため、
既存の Dashboard 承認・手動レビュー・自動マージ無効を維持する。
本書は計画であり、現在の Forgejo 運用を実装済みとして置き換えるものではない。

## 望ましい構成

| 項目 | 状態と制約 |
| --- | --- |
| リポジトリ | 公開の `takanao14/devcontainer` が正本。Git の既存コミット ID と必要なタグを保持 |
| CI | GitHub-hosted `ubuntu-24.04` で `make check`、実行時間上限10分 |
| 起動条件 | main の push、通常の `pull_request`、手動実行 |
| CI 権限 | `contents: read`、checkout の `persist-credentials: false` |
| 依存更新 | 既存の2日待機、公開日時不明候補の拒否、Dashboard 承認、自動マージ無効 |
| ローカル環境 | 作業ディレクトリ、イメージ参照、選択記録、状態ボリューム、バックアップを保持 |
| Forgejo | 過去の PR・Issue・CI・公開成果物の参照先。切り替え後は通常更新を停止 |

CI は Docker の利用、ロック再生成、コンテナ起動、認証状態の取得を必要としない。
トークンの権限は GitHub の[最小権限設定](https://docs.github.com/en/actions/tutorials/authenticate-with-github_token)に従う。
main は直接更新・force push を通常手順とせず、PR と静的検査を更新条件とする。
GitHub の契約・公開範囲に応じたブランチ保護の利用可否は設定時に確認する。

Git のコピーと Forgejo の PR・Issue・実行履歴は別の対象とする。
過去の番号付きリンクは Forgejo に残し、新規の PR・Issue は GitHub で作成する。
履歴の一括移植とレジストリ成果物の再公開は本計画の対象に含めない。

## 実装手順

### 1. 移行先と更新経路の準備

- 空の公開 GitHub リポジトリ `takanao14/devcontainer` を用意する。
  作業ツリーだけでなく、移す Git 履歴の公開範囲も確認する。
  認証バックアップと `.local-builds/` は移さない。
- 移行中の更新先は Forgejo に限定する。未完了の人手の PR はマージまたは移行方針を決め、
  Renovate の未完了 PR は再提案対象として記録する。

### 2. GitHub 用 CI と文書の準備

- `.github/workflows/checks.yml` を用意する。checkout は `actions/checkout` の
  レビュー済みコミット SHA に固定し、公開後48時間の方針に従って選定する。
  Forgejo checkout の URL・SHA をそのまま流用しない。
- Bash・Make・Git・jq・ShellCheck・Node.js・npm の利用を確認し、不足分を用意する。
  Mike Farah yq は既存の固定値と Linux x64 の公開チェックサムで導入する。
  runner の別実装の `yq` を名前だけで採用しない。
- `tests/test_static_ci.sh` に GitHub workflow の検証を追加する。
  読み取り権限、checkout、起動条件、Docker・Secret 不要の `make check` を確認する。
- `scripts/check-shell.sh` は `.github/workflows/` の YAML 内のシェルも検査する。
  準備中は両 workflow を検査し、切り替え後は廃止した Forgejo workflow の依存を整理する。
- README は切り替え完了までは現行の運用を記述する。全体計画・CI 文書の将来構成は
  GitHub を正本とし、過去の Forgejo 検証記録と区別する。
- 準備変更は Forgejo の PR でレビュー・マージし、そこで `make check` を確認する。

### 3. Git 履歴と CI の確認

- [GitHub の複製手順](https://docs.github.com/en/repositories/creating-and-managing-repositories/duplicating-a-repository)を参考に、
  main と必要なタグ・継続するブランチを空の移行先に送る。
  通常チェックアウトからの `push --mirror` は使わず、PR 用の内部参照・stash・
  不要な追跡参照を移行対象に含めない。
- 切り替え元・先の main とタグのコミット ID を照合する。
  コピーした main、テスト PR、手動実行で GitHub CI を確認する。
- 認証情報を必要としない PR の検査と、GitHub Actions 用 checkout の更新検出を確認する。

### 4. Renovate の切り替え

- 既存のホスト型 App に、[公式の導入手順](https://docs.renovatebot.com/getting-started/installing-onboarding/)に従って
  対象リポジトリを選択してアクセスを許可する。既存の `renovate.json` を使用する。
  初回の設定変更提案がある場合は、既存の承認・2日待機の方針を維持してレビューする。
- Dashboard と mise・ブートストラップ・GitHub Actions の検出、公開日時の取得、
  承認後の更新 PR と CI を確認する。実際の更新候補がなければ PR 作成は未確認と記録する。
- GitHub 側の成立後に、既存 `takanao/renovate` の対象一覧からこのリポジトリだけを外す。
  他の対象や共有のトークン・IPv4 設定は保持する。

### 5. 正本の切り替え

- 更新を一時的に止め、Forgejo main の最終コミットを GitHub に反映して一致を確認する。
- ローカルの Forgejo remote は `forgejo` として保持し、GitHub を `origin` とする。
  ブランチの upstream と PR の送信方法を GitHub に合わせる。
- README と CI 文書の通常手順を GitHub に更新する。Forgejo workflow は通常実行から外し、
  履歴上の PR・実行結果へのリンクは出典として保持する。
- GitHub の CI・更新経路が成立した後、Forgejo 側を参照用に固定する。
  旧リポジトリやレジストリを削除せず、自動同期は通常運用に含めない。

## 検証と完了条件

- 必要なコミット・タグが一致し、GitHub が唯一の通常更新先となっている。
- GitHub の main・PR・手動 CI が成功し、Secret・Docker・レジストリに依存しない。
- Renovate の設定・検出・承認経路が確認され、同じリポジトリに2つの bot が更新を提案しない。
- ローカルの `make check` とイメージ世代管理の候補表示が成功する。
- パス・ソース・状態ボリューム・選択中／復帰用の参照が保持される。
  ホスティング変更だけでは、イメージ再ビルド・コンテナ再作成・再ペアリングを必要としない。
- 作業ディレクトリを移動する場合は、パス由来の状態識別子が変わるため別の移行手順とする。

## 復帰

切り替え前は Forgejo を正本として継続する。切り替え後に問題がある場合は、
GitHub の更新を止め、追加コミットを確認して Forgejo に反映してから正本を戻す。
両側への同時更新・force push による履歴の巻き戻しを復帰の手順に含めない。
ローカルのコンテナ・ボリュームは、ホスティングの復帰操作では変更しない。

## 準備段階の検証記録

2026-10-13 に GitHub の認証先 `takanao14` と移行先の未作成を確認した。
Gitleaks 8.30.1 を公式チェックサムで検証し、移行対象 main の履歴から検出はなかった。
この検査は秘密情報が存在しないことの完全な保証ではなく、内部ホスト名や過去の
設計・運用記録も公開対象に含まれる。
checkout v7.0.1 の正式リリースと公式タグを確認した結果、固定 SHA は Forgejo で
使用していた値と同じだった。GitHub workflow は公式 `actions/checkout` を参照する。
公開の `takanao14/devcontainer` は空の移行先として作成済み。
Forgejo の未完了 PR は準備変更の作成前にはなかった。GitHub 用 workflow と
両 workflow の静的検査を準備し、ローカルの `make check` を確認した。
GitHub への Git 履歴コピー、GitHub CI の実行、Renovate App の対象追加、
正本の切り替えは準備変更のマージ後に行う。
