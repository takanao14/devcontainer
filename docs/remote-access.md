# コンテナ内 CLI のリモート利用調査

## 利用モデル

プロジェクトごとのコンテナ内で Claude Code / Codex を実行し、スマホから指示、承認、
結果確認を行う。ソース、CLI の認証と履歴、実行権限はプロジェクト単位で分離する。
リモートの利用者にも、コンテナ内プロセスと同じマウント範囲・実行権限を適用する。
Claude の前面実行はホストの tmux で維持できる。
Codex は標準の管理 daemon を使用し、操作端末から独立したコンテナの稼働を採用する方針。
ペアリングと環境の起動・停止は別操作とする。
通常利用に独自の daemon 管理やコンテナの自動再起動を必要としない。

以下は 2026-10-07 時点の調査結果。利用者のコンテナ環境で Claude と Codex の
リモート接続、スマホからの承認・拒否、tmux 切り離し後の継続を確認済み。
Codex は、初回ペアリング後に daemon を停止し、コンテナを削除・再作成しても、
同じ状態ボリュームで起動すれば再ペアリングなしで接続を再利用できることを利用者確認済み。
スマホ側の接続登録は保持した試験であり、登録の削除や状態ボリュームの削除は対象外。
Codex の起動・停止・ペアリング・シェル接続は独立したランチャー操作として実装済み。
ラッパーの終了処理はモックによる単体テストと、ARM64 の実コンテナ内の
モック CLI による端末なしでの継続・SIGTERM のスモークテストで検証済み。
専用ランチャーでの実際のペアリングとスマホ側の切断確認は未実施。
手元のホストの Codex 0.160.1 では、ヘルプ表示により `remote-control`、
`start` / `stop` / `pair` の存在を確認した。接続の有効化やペアリングは実行していない。

## Claude Code

Remote Control は `claude remote-control` のサーバーモード、
`claude --remote-control` の対話モード、既存会話での `/remote-control` に対応する。
スマホは Claude アプリまたは Web のセッションに接続する。
CLI から外向き HTTPS で接続し、ホストやコンテナの待ち受けポート公開を必要としない。
claude.ai の対象サブスクリプションによる認証が必要で、API キー認証には対応しない。
機能フラグ評価を無効にする設定も Remote Control を無効にする。
[公式資料](https://code.claude.com/docs/en/remote-control)

サーバーモードでは `--spawn=session` で一つのセッションに限定でき、
`--permission-mode default` をサーバーの引数として指定できる。
既存ランチャーは `claude --permission-mode default` に引数を追加する方式だが、
公式資料はサーバーサブコマンドより前の一部グローバル引数を拒否するとしている。
リモート用の起動コマンドは対話用と区別して組み立てる必要がある。
[起動モードと引数](https://code.claude.com/docs/en/remote-control#start-a-remote-control-session)

プロセスの停止中はリモート操作できない。会話の保存と、オンラインの接続維持は別の機能。
停止後のサーバーセッションの復帰には時間制限もあり、保存された履歴があっても
同じリモートセッションへの自動復帰を保証できない。
[復帰と制約](https://code.claude.com/docs/en/remote-control#resume-sessions-after-stopping-the-server)

## Codex

CLI に実験的なリモート接続経路がある。`codex remote-control` は前面で動作し、
`codex remote-control start` はリモート接続を有効にした app-server daemon を起動する。
daemon 起動後の `codex remote-control pair` は短時間有効な手動ペアリングコードを発行する。
一般向けのデスクトップアプリのモバイル接続手順とは区別する。
[公式コマンド資料](https://learn.chatgpt.com/docs/developer-commands#codex-remote-control)

0.160.1 の daemon 実装は管理用の専用パッケージを使用する。
`CODEX_HOME/packages/app-server-daemon` にパッケージを配置でき、既存の管理パッケージが
あればそれを再利用する。条件に合う管理 daemon は自動更新できる。
daemon の `settings.json` にある `updater.autoUpdateEnabled` は、
現在のイメージの `DISABLE_UPDATES` とは別の設定として検討が必要。
[0.160.1 の実装資料](https://github.com/openai/codex/blob/rust-v0.160.1/codex-rs/app-server-daemon/README.md)

現在の Dockerfile は npm インストールで、`CODEX_HOME` 全体を状態ボリュームに保存する。
管理 daemon を使用すると、実行パッケージまでボリューム側に残り、イメージ切り替え後も
旧パッケージが再利用される可能性がある。この点は資料と構成からの推論である。
Codex のリモート接続は確認済みだが、使用した起動方式とパッケージ構成は未記録。
初回起動でパッケージ不足が報告された場合は、エラーに応じてインストール方式を見直す。

0.160.1 の前面モードは一時ディレクトリ内の専用 Unix ソケットで app-server を動かす。
一方、`remote-control pair` は管理 daemon のソケットに接続する。
このため、前面モードと別端末の `pair` を単純に組み合わせる手順は使用しない。
前面モードは通常の対話 TUI ではなく、リモート用の app-server を前面で維持するコマンド。
[前面モードの実装](https://github.com/openai/codex/blob/rust-v0.160.1/codex-rs/cli/src/remote_control_cmd.rs)、
[pair の接続先](https://github.com/openai/codex/blob/rust-v0.160.1/codex-rs/app-server-daemon/src/lib.rs)

## Codex のリモート用ランチャー

既存のイメージを使用し、再ビルドは不要。Codex 用のコンテナは端末から独立して稼働する。

```sh
make codex-remote-start NETWORK=bridge
make codex-remote-pair
make codex-remote-shell
make codex-remote-status
make codex-remote-stop
```

ランチャーはコンテナ内で認証状態を確認し、承認設定を維持して daemon を起動する。
`start` はコードを発行せず、`pair` は初回登録や新しいスマホの追加時だけ実行する。
`shell` は稼働中のコンテナへの接続であり、`exit` でもリモート環境は継続する。
`stop` は daemon を停止してからコンテナを終了し、状態ボリュームを保持する。
daemon の停止待ちは10秒、強制停止までの猶予は追加の2秒。停止失敗は通知し、
コンテナ自体の停止も試みる。Docker のコンテナ停止猶予は15秒。
すべての操作に同じ `PROJECT` を指定する。マウントなどの起動設定が変わった場合は、
稼働中の環境を停止してから再起動する。同じタグのイメージを更新した場合も停止・再起動が必要。
`stop`、`pair`、`shell`、`status` は、起動時の `MOUNTS` や `NETWORK` の指定を必要としない。
`codex-remote` は `start` の別名。コンテナ終了シグナルと起動失敗でも停止処理を試みる。
通常の `shell`、`codex`、`claude` 操作には、この終了処理を適用しない。

検証には `make test` と `make smoke-remote` を使用する。専用操作でのペアリング、
`shell` の終了後の接続維持、`stop` 後のスマホ側の切断、再起動後の再接続は実機確認が必要。

## Codex の手動起動手順

ホストの tmux セッション内で、このリポジトリからコンテナのシェルを起動する。

```sh
tmux new-session -s devcontainer-images-codex
make shell NETWORK=bridge
```

既存の前面モードが動作中なら `Ctrl-C` で終了し、同じコンテナのシェルに戻る。
コンテナ内でプロジェクト別の認証状態を確認し、管理 daemon を起動する。
承認は既存ランチャーと同じ `on-request`、主な分離境界はコンテナとする。

```sh
codex login status
codex -c 'sandbox_mode="danger-full-access"' \
  -c 'approval_policy="on-request"' remote-control start
codex remote-control pair
```

スマホ側のペアリング画面に、今回発行された手動コードを有効期限内に入力する。
以前のコードは使用しない。接続できた場合は `/workspace/devcontainer-images` を対象に、
ファイルを変更しない依頼を試す。
リモート接続は利用者確認済み。以下の管理 daemon 手順と同じ経路かは未記録。

起動やコード発行で失敗した場合は、その段階とエラーを記録する。
コード発行後も「ペアリングセッションが見つかりません」となる場合は、
CLI とスマホの認証アカウント、有効期限、アプリの対応状況を確認する。
接続名、コード、認証情報は共有しない。

接続できたら tmux を `Ctrl-b`、`d` で切り離し、スマホから引き続き指示できるか確認する。
ホストでは `tmux attach-session -t devcontainer-images-codex` で戻れる。
終了はコンテナ内で `codex remote-control stop` を実行し、その後 `exit` でシェルを終了する。
`start` はシェルに戻るが、シェルの終了はランチャーのコンテナを終了させ、
その中の daemon も停止する。daemon はコンテナを存続させる仕組みではない。

## 検証候補の構成

- 最初は bridge 接続で、プロジェクトごと、CLI ごとに独立したリモート用コンテナを使用する。
- ホストの tmux 内で現在のシェルランチャーを使用する。tmux の切り離しは CLI や
  コンテナの終了と区別する。tmux をコンテナ内に置く方式はこの試験の前提に含めない。
- 会話履歴の保存、接続状態、コンテナの再起動、会話の再開をそれぞれ区別する。
- CLI の承認はリモートでも有効とする。推論サービスへ接続できることだけでなく、
  スマホから承認・拒否ができることを検証する。
- 同一プロジェクトの複数セッションによる編集競合は、セッションの使い分けや worktree で扱う。
- ホストのスリープ中や Docker の停止中には作業できない。

通常のランチャーは前面実行・終了時削除、Codex のリモート用ランチャーは端末から独立した
起動・明示的な停止の方式。実際の Codex とスマホでの専用操作による終了動作は未検証。
ライフサイクルの要件は[実装計画](devcontainer-implementation-plan.md#リモート利用のライフサイクル)に記載する。

## 検証順序

1. Claude のリモート接続とスマホからの承認・拒否は確認済み。
2. Codex のリモート接続とスマホからの承認・拒否は確認済み。
3. コンテナ内のリモート操作が、明示したソースと権限の範囲で実行されることを確認する。
4. tmux 切り離し後の継続と、Codex のコンテナ再作成後の接続登録の再利用は確認済み。
   通信断後の再接続と、実行中の会話・作業の復帰は別途確認する。
5. 別プロジェクトを同時に起動し、スマホ上の識別と状態の分離を確認する。
6. ランチャーの起動・停止・ペアリング・操作端末の接続を分離し、終了処理を検証する。
   IDE の Dev Container 起動との統合も確認する。

ペアリングコード、セッション URL、認証情報を検証ログや文書に保存しない。
